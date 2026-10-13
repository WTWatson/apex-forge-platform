/**
 * This file is part of the Forge Platform project
 *
 * The unit a developer writes to send records to another system: they say what one
 * call does with its records, and the platform moves it out of the transaction,
 * splits the records into calls, retries, saves what changed and records failures.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public abstract with sharing class ForgeIntegration {

    private static final Integer CALLOUT_SECONDS_PER_TRANSACTION = 120;
    private static final Integer CHAINED_JOBS_IN_TRIAL_AND_DEVELOPER_ORGS = 5;
    private static final List<Integer> RETRY_DELAY_MINUTES = new List<Integer>{ 1, 5 };
    private static final Set<String> integrationsSavingResults = new Set<String>();

    @TestVisible
    private static Job followOnHeldForTest;

    private transient String currentCallKey;
    private transient Integer connectionsOpened;
    private transient List<ForgeHttp.Connection> callConnections;
    private transient Integer longestWaitSeconds;

    /** Sends these records to the other system in a background job after the current transaction; never calls out in the caller's transaction. */
    public static void start(ForgeIntegration integration, List<SObject> records)
    {
        if (records == null || records.isEmpty()) { return; }
        if (integrationsSavingResults.contains(integration.name())) { return; }

        if (Limits.getQueueableJobs() >= Limits.getLimitQueueableJobs())
        {
            throw new StartRefusedException(integration.name() + ' cannot start: this transaction may queue only '
                + Limits.getLimitQueueableJobs() + ' job(s) and has queued them. In a Queueable, batch or future'
                + ' method, start an integration once, with all its records.');
        }

        System.enqueueJob(new Job(integration, integration.callsFor(idsOf(integration, records)), 0));
    }

    /** Sends one call's worth of records to the other system and sets on them what the reply changes; it makes no DML. */
    protected abstract void run(List<SObject> records);

    /** How many records go in one call; override it to match what the other system accepts. 1 unless overridden. */
    protected virtual Integer recordsPerCall()
    {
        return 1;
    }

    /** Whether the other system can safely receive the same POST or PATCH twice, so those calls may be retried. False unless overridden. */
    protected virtual Boolean repeatsAreSafe()
    {
        return false;
    }

    /** Whether records are read and saved with the running user's permissions or in system mode. User mode unless overridden. */
    protected virtual AccessLevel accessLevel()
    {
        return AccessLevel.USER_MODE;
    }

    /** Runs after the job has saved what its calls changed, with the records that saved, for any other DML the integration needs. */
    protected virtual void afterCalls(List<SObject> records) {}

    /** Opens a connection to the system behind the Named Credential with this name, keyed so a retried call repeats the same key. */
    protected ForgeHttp.Connection connection(String namedCredential)
    {
        connectionsOpened++;
        ForgeHttp.Connection opened = ForgeHttp.connection(namedCredential)
            .idempotencyKey(connectionsOpened == 1 ? currentCallKey : currentCallKey + '-c' + connectionsOpened);
        longestWaitSeconds = Math.max(longestWaitSeconds, opened.waitsUpToSeconds());
        callConnections.add(opened);
        return opened;
    }

    /** Raised when an integration starts in a transaction that may queue no more jobs, such as a second start inside a Queueable. */
    public class StartRefusedException extends Exception {}

    private String name()
    {
        return String.valueOf(this).split(':')[0];
    }

    private static List<Id> idsOf(ForgeIntegration integration, List<SObject> records)
    {
        List<Id> ids = new List<Id>();
        for (SObject record : records)
        {
            if (record.Id == null)
            {
                throw new StartRefusedException(integration.name() + ' cannot start for a record that is not saved yet;'
                    + ' start it after insert.');
            }
            ids.add(record.Id);
        }
        return ids;
    }

    private List<Call> callsFor(List<Id> ids)
    {
        List<Call> calls = new List<Call>();
        Integer size = Math.max(1, recordsPerCall());
        for (Integer first = 0; first < ids.size(); first += size)
        {
            List<Id> callIds = new List<Id>();
            for (Integer i = first; i < Math.min(first + size, ids.size()); i++) { callIds.add(ids[i]); }
            calls.add(new Call(callIds));
        }
        return calls;
    }

    private void runJob(Job job)
    {
        JobOutcome outcome = new JobOutcome(name());
        Map<Id, SObject> recordsById = readRecords(job.recordIds());
        Long millisWaited = 0;
        longestWaitSeconds = 0;

        for (Integer i = 0; i < job.calls.size(); i++)
        {
            Call call = job.calls[i];
            if (!hasRoomForAnotherCall(millisWaited))
            {
                outcome.unsent.addAll(remainingFrom(job.calls, i));
                break;
            }
            Long callStarted = System.currentTimeMillis();
            sendCall(call, recordsById, outcome);
            millisWaited += System.currentTimeMillis() - callStarted;
        }

        List<SObject> saved = saveChanges(outcome);
        if (!saved.isEmpty()) { afterCalls(saved); }
        queueFollowOn(job, outcome);
        if (!outcome.failures.isEmpty()) { Database.insert(outcome.failures, AccessLevel.SYSTEM_MODE); }
    }

    private Map<Id, SObject> readRecords(List<Id> ids)
    {
        Schema.DescribeSObjectResult objectType = ids[0].getSObjectType().getDescribe(SObjectDescribeOptions.DEFERRED);
        List<String> fieldNames = new List<String>();
        for (Schema.SObjectField field : objectType.fields.getMap().values())
        {
            Schema.DescribeFieldResult describe = field.getDescribe();
            if (isReadable(describe)) { fieldNames.add(describe.getName()); }
        }
        String query = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + objectType.getName() + ' WHERE Id IN :ids';
        return new Map<Id, SObject>(Database.queryWithBinds(query, new Map<String, Object>{ 'ids' => ids }, accessLevel()));
    }

    private Boolean isReadable(Schema.DescribeFieldResult field)
    {
        Schema.DisplayType type = field.getType();
        Boolean compoundOrBinary = type == Schema.DisplayType.ADDRESS || type == Schema.DisplayType.LOCATION
            || type == Schema.DisplayType.BASE64;
        return !compoundOrBinary && (accessLevel() == AccessLevel.SYSTEM_MODE || field.isAccessible());
    }

    private Boolean hasRoomForAnotherCall(Long millisWaited)
    {
        Integer secondsLeft = CALLOUT_SECONDS_PER_TRANSACTION - (Integer) (millisWaited / 1000);
        Integer secondsNeeded = longestWaitSeconds > 0 ? longestWaitSeconds : 30;
        return Limits.getCallouts() < Limits.getLimitCallouts() && secondsLeft >= secondsNeeded;
    }

    private void sendCall(Call call, Map<Id, SObject> recordsById, JobOutcome outcome)
    {
        List<SObject> records = new List<SObject>();
        List<Id> missing = new List<Id>();
        for (Id recordId : call.recordIds)
        {
            if (recordsById.containsKey(recordId)) { records.add(recordsById.get(recordId)); }
            else { missing.add(recordId); }
        }
        if (!missing.isEmpty())
        {
            outcome.addFailure(missing, null, null, 'The record was deleted, or the user who started the integration can no longer see it.');
        }
        if (records.isEmpty()) { return; }

        List<Map<String, Object>> before = new List<Map<String, Object>>();
        for (SObject record : records) { before.add(new Map<String, Object>(record.getPopulatedFieldsAsMap())); }

        currentCallKey = call.key;
        connectionsOpened = 0;
        callConnections = new List<ForgeHttp.Connection>();
        try
        {
            run(records);
            outcome.completed.add(new CompletedCall(records, before));
        }
        catch (ForgeHttp.CalloutFailureException failure)
        {
            Boolean retryAllowed = failure.isWorthRetrying() && (repeatsAreSafe() || isSafeToRepeat(failure.method));
            if (retryAllowed && call.attempt < RETRY_DELAY_MINUTES.size() + 1)
            {
                outcome.retries.add(call.nextAttempt());
            }
            else
            {
                String reason = failure.getMessage() + ' after ' + call.attempt + ' attempt(s).';
                outcome.addFailure(call.recordIds, failure.status, failure.replyBody, reason);
            }
        }
        catch (CalloutException notSent)
        {
            outcome.addFailure(call.recordIds, null, null, 'The call could not be sent: ' + notSent.getMessage());
        }
        catch (Exception unexpected)
        {
            // A request no test described must fail that test, not become a failure record.
            if (unexpected.getTypeName() == 'ForgeHttpMock.UnmatchedRequestException') { throw unexpected; }
            ForgeHttp.Response reply = lastReplyOfThisCall();
            String reason = 'The integration failed while handling the reply: ' + unexpected.getTypeName() + ': ' + unexpected.getMessage();
            outcome.addFailure(call.recordIds, reply?.status, reply?.body, reason);
        }
    }

    private ForgeHttp.Response lastReplyOfThisCall()
    {
        for (Integer i = callConnections.size() - 1; i >= 0; i--)
        {
            if (callConnections[i].lastReply() != null) { return callConnections[i].lastReply(); }
        }
        return null;
    }

    private static Boolean isSafeToRepeat(String method)
    {
        return method == 'GET' || method == 'PUT' || method == 'DELETE';
    }

    private static List<Call> remainingFrom(List<Call> calls, Integer first)
    {
        List<Call> remaining = new List<Call>();
        for (Integer i = first; i < calls.size(); i++) { remaining.add(calls[i]); }
        return remaining;
    }

    private List<SObject> saveChanges(JobOutcome outcome)
    {
        List<SObject> changes = new List<SObject>();
        List<SObject> changedRecords = new List<SObject>();
        for (CompletedCall completed : outcome.completed)
        {
            for (Integer i = 0; i < completed.records.size(); i++)
            {
                SObject change = completed.changeTo(i);
                if (change != null)
                {
                    changes.add(change);
                    changedRecords.add(completed.records[i]);
                }
            }
        }
        if (changes.isEmpty()) { return changedRecords; }

        List<SObject> saved = new List<SObject>();
        integrationsSavingResults.add(name());
        try
        {
            List<Database.SaveResult> results = Database.update(changes, false, accessLevel());
            for (Integer i = 0; i < results.size(); i++)
            {
                if (results[i].isSuccess()) { saved.add(changedRecords[i]); }
                else { outcome.addSaveFailure(changes[i], results[i].getErrors()); }
            }
        }
        finally
        {
            integrationsSavingResults.remove(name());
        }
        return saved;
    }

    private void queueFollowOn(Job job, JobOutcome outcome)
    {
        List<Call> calls = new List<Call>(outcome.unsent);
        calls.addAll(outcome.retries);
        if (calls.isEmpty()) { return; }

        if (job.chainDepth + 1 >= chainedJobLimit())
        {
            for (Call call : calls)
            {
                outcome.addFailure(call.recordIds, null, null,
                    'Not sent: the org allows no more chained jobs, so the call could not be passed to a follow-on job.');
            }
            return;
        }

        Job followOn = new Job(this, calls, job.chainDepth + 1);
        if (Test.isRunningTest())
        {
            followOnHeldForTest = followOn;
            return;
        }
        Integer delayMinutes = outcome.retries.isEmpty() ? 0 : RETRY_DELAY_MINUTES[outcome.retries[0].attempt - 2];
        System.enqueueJob(followOn, delayMinutes);
    }

    private static Integer chainedJobLimit()
    {
        Organization org = [SELECT OrganizationType, TrialExpirationDate FROM Organization LIMIT 1];
        Boolean limitedOrg = org.TrialExpirationDate != null || org.OrganizationType == 'Developer Edition';
        return limitedOrg ? CHAINED_JOBS_IN_TRIAL_AND_DEVELOPER_ORGS : 2147483647;
    }

    /** Runs the follow-on job a test's job passed on, such as a retry, as Salesforce would have queued it. */
    @TestVisible
    private static void runFollowOnHeldForTest()
    {
        Job held = followOnHeldForTest;
        followOnHeldForTest = null;
        held.execute(null);
    }

    private class Job implements Queueable, Database.AllowsCallouts
    {
        private final ForgeIntegration integration;
        private final List<Call> calls;
        private final Integer chainDepth;

        private Job(ForgeIntegration integration, List<Call> calls, Integer chainDepth)
        {
            this.integration = integration;
            this.calls = calls;
            this.chainDepth = chainDepth;
        }

        public void execute(QueueableContext context)
        {
            integration.runJob(this);
        }

        private List<Id> recordIds()
        {
            List<Id> ids = new List<Id>();
            for (Call call : calls) { ids.addAll(call.recordIds); }
            return ids;
        }
    }

    private class Call
    {
        private final List<Id> recordIds;
        private final String key;
        private final Integer attempt;

        private Call(List<Id> recordIds)
        {
            this(recordIds, UUID.randomUUID().toString(), 1);
        }

        private Call(List<Id> recordIds, String key, Integer attempt)
        {
            this.recordIds = recordIds;
            this.key = key;
            this.attempt = attempt;
        }

        private Call nextAttempt()
        {
            return new Call(recordIds, key, attempt + 1);
        }
    }

    private class CompletedCall
    {
        private final List<SObject> records;
        private final List<Map<String, Object>> before;

        private CompletedCall(List<SObject> records, List<Map<String, Object>> before)
        {
            this.records = records;
            this.before = before;
        }

        private SObject changeTo(Integer index)
        {
            SObject record = records[index];
            Map<String, Object> earlier = before[index];
            SObject change = record.getSObjectType().newSObject(record.Id);
            Boolean changed = false;
            for (String field : record.getPopulatedFieldsAsMap().keySet())
            {
                Object now = record.get(field);
                if (field != 'Id' && (!earlier.containsKey(field) || earlier.get(field) != now))
                {
                    change.put(field, now);
                    changed = true;
                }
            }
            return changed ? change : null;
        }
    }

    private class JobOutcome
    {
        private final String integrationName;
        private final List<CompletedCall> completed = new List<CompletedCall>();
        private final List<Call> retries = new List<Call>();
        private final List<Call> unsent = new List<Call>();
        private final List<Integration_Failure__c> failures = new List<Integration_Failure__c>();

        private JobOutcome(String integrationName)
        {
            this.integrationName = integrationName;
        }

        private void addFailure(List<Id> recordIds, Integer status, String replyBody, String reason)
        {
            failures.add(new Integration_Failure__c(
                Integration__c = integrationName,
                Record_Ids__c = String.join(recordIds, ','),
                Status__c = status,
                Reply_Body__c = replyBody == null ? null : replyBody.abbreviate(131072),
                Reason__c = reason.abbreviate(32768)
            ));
        }

        private void addSaveFailure(SObject change, List<Database.Error> errors)
        {
            List<String> messages = new List<String>();
            for (Database.Error error : errors) { messages.add(error.getMessage()); }
            Map<String, Object> values = new Map<String, Object>(change.getPopulatedFieldsAsMap());
            values.remove('Id');
            addFailure(new List<Id>{ change.Id }, null, JSON.serialize(values),
                'The reply arrived but the record could not be saved: ' + String.join(messages, '; '));
        }
    }
}
