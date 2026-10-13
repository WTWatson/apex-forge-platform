@IsTest
private class ForgeIntegrationTest
{
    // These tests start integrations directly and use only standard Account fields, so
    // they run in any org that has the platform. The scenario through an Account trigger
    // is tested in test-support (ForgeIntegrationOnAccountTest).

    private static final String ERP = 'ForgeTestErp';

    private class CustomerNumber
    {
        String customerNumber;
    }

    /** Posts customers to the ERP and writes the number it answers into the Account Number. */
    private virtual class RecordErpNumbers extends ForgeIntegration
    {
        private final Integer perCall;
        private final Boolean safeToRepeat;

        RecordErpNumbers(Integer perCall, Boolean safeToRepeat)
        {
            this.perCall = perCall;
            this.safeToRepeat = safeToRepeat;
        }

        protected override void run(List<SObject> records)
        {
            List<Account> accounts = (List<Account>) records;
            List<Map<String, String>> customers = new List<Map<String, String>>();
            for (Account account : accounts)
            {
                customers.add(new Map<String, String>{ 'salesforceId' => account.Id, 'name' => account.Name });
            }
            List<CustomerNumber> numbers = (List<CustomerNumber>) connection(ERP).post('/customers', customers)
                .readAs(List<CustomerNumber>.class);
            for (Integer i = 0; i < accounts.size(); i++)
            {
                accounts[i].AccountNumber = 'ERP ' + numbers[i].customerNumber;
                if (accounts[i].Name.startsWith('Broken')) { accounts[i].Name = ''; }
            }
        }

        protected override Integer recordsPerCall() { return perCall; }

        protected override Boolean repeatsAreSafe() { return safeToRepeat; }

        protected virtual override void afterCalls(List<SObject> records)
        {
            List<Task> welcomes = new List<Task>();
            for (SObject record : records) { welcomes.add(new Task(WhatId = record.Id, Subject = 'Welcome')); }
            insert welcomes;
        }
    }

    /** Welcomes the new customers, then fails, as a rejected Task insert would. */
    private class RecordErpNumbersButFailToWelcome extends RecordErpNumbers
    {
        RecordErpNumbersButFailToWelcome() { super(1, true); }

        protected override void afterCalls(List<SObject> records)
        {
            super.afterCalls(records);
            throw new DmlException('Welcome tasks are closed today');
        }
    }

    /** Uses every job the transaction may still queue, as other trigger logic could. */
    private class RecordErpNumbersAndQueueEveryJob extends RecordErpNumbers
    {
        RecordErpNumbersAndQueueEveryJob() { super(1, true); }

        protected override void afterCalls(List<SObject> records)
        {
            while (Limits.getQueueableJobs() < Limits.getLimitQueueableJobs()) { System.enqueueJob(new DoNothing()); }
        }
    }

    /** Creates the customer in the ERP, then reads back its credit limit; a POST and then a GET in one call. */
    private class CreateCustomersWithCreditLimits extends ForgeIntegration
    {
        private final Boolean safeToRepeat;

        CreateCustomersWithCreditLimits(Boolean safeToRepeat)
        {
            this.safeToRepeat = safeToRepeat;
        }

        protected override void run(List<SObject> records)
        {
            Account account = (Account) records[0];
            ForgeHttp.Connection erp = connection(ERP);
            account.AccountNumber = erp.post('/customers', account.Name).body;
            account.AnnualRevenue = Decimal.valueOf(erp.get('/credit-limits').body);
        }

        protected override Boolean repeatsAreSafe() { return safeToRepeat; }
    }

    /** Reads each customer's rating and credit limit from the ERP; two GETs in one call. */
    private class LookUpRatingsAndLimits extends ForgeIntegration
    {
        protected override void run(List<SObject> records)
        {
            Account account = (Account) records[0];
            ForgeHttp.Connection erp = connection(ERP);
            account.Rating = erp.get('/ratings').body;
            account.AnnualRevenue = Decimal.valueOf(erp.get('/credit-limits').body);
        }
    }

    /** Reads each customer's rating from an ERP that may take this many seconds to answer. */
    private class LookUpSlowRatings extends ForgeIntegration
    {
        private final Integer seconds;

        LookUpSlowRatings(Integer seconds)
        {
            this.seconds = seconds;
        }

        protected override void run(List<SObject> records)
        {
            Account account = (Account) records[0];
            account.Rating = connection(ERP).waitsUpToSeconds(seconds).get('/ratings').body;
        }
    }

    /** Reads each customer's credit rating from the ERP; a GET, so it is retried without being told. */
    private class LookUpCreditRatings extends ForgeIntegration
    {
        protected override void run(List<SObject> records)
        {
            Account account = (Account) records[0];
            account.Rating = connection(ERP).get('/ratings/' + account.Id).body;
        }
    }

    /** Reads each customer's credit rating from the ERP's JSON; a reply in another shape makes run() throw. */
    private class ReadCreditRatingsFromJson extends ForgeIntegration
    {
        protected override void run(List<SObject> records)
        {
            Account account = (Account) records[0];
            account.Description = 'Rating asked of the ERP';
            String reply = connection(ERP).get('/ratings/' + account.Id).body;
            account.Rating = (String) ((Map<String, Object>) JSON.deserializeUntyped(reply)).get('rating');
        }
    }

    /** Asks the ERP about a path no test describes. */
    private class AskSomethingUndescribed extends ForgeIntegration
    {
        protected override void run(List<SObject> records)
        {
            connection(ERP).get('/nobody-described-this');
        }
    }

    private class DoNothing implements Queueable
    {
        public void execute(QueueableContext context) {}
    }

    @IsTest
    static void aSingleRecordIsSentAndWhatTheReplyChangedIsSaved()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(1));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, false), new List<Account>{ acme });
        Assert.areEqual(0, customers.requests().size(), 'nothing is sent in the caller\'s transaction');
        Test.stopTest();

        Assert.areEqual('ERP C-1', [SELECT AccountNumber FROM Account WHERE Id = :acme.Id].AccountNumber);
        Assert.areEqual(1, customers.requests().size());
        Assert.isTrue(customers.requests()[0].getBody().contains(acme.Id), 'the customer carries its Salesforce Id');
        Assert.areEqual(1, [SELECT COUNT() FROM Task WHERE WhatId = :acme.Id], 'afterCalls runs after the save');
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);
    }

    @IsTest
    static void twoHundredRecordsGoInFourCallsFromOneJob()
    {
        List<Account> accounts = newAccounts(200);
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(50));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(50, false), accounts);
        Test.stopTest();

        Assert.areEqual(4, customers.requests().size());
        Assert.areEqual(1, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable']);
        Assert.areEqual(200, [SELECT COUNT() FROM Account WHERE AccountNumber LIKE 'ERP C-%']);
        Assert.areEqual(200, [SELECT COUNT() FROM Task]);
    }

    @IsTest
    static void callsBeyondWhatOneJobMaySendGoToAFollowOnJob()
    {
        List<Account> accounts = newAccounts(101);
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(1));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, false), accounts);
        Test.stopTest();

        Assert.areEqual(100, customers.requests().size(), 'a job sends at most 100 calls');
        Assert.areEqual(100, [SELECT COUNT() FROM Account WHERE AccountNumber = 'ERP C-1'], 'what was sent is saved');

        ForgeIntegration.runFollowOnHeldForTest();

        Assert.areEqual(101, customers.requests().size());
        Assert.areEqual(101, [SELECT COUNT() FROM Account WHERE AccountNumber = 'ERP C-1']);
        Assert.isNull(ForgeIntegration.followOnHeldForTest, 'nothing is left to send');
    }

    @IsTest
    static void aReplyOutsideTwoHundredsBecomesAFailureRecord()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.connection(ERP).post('/customers').reply(400, '{"error":"name missing"}');

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, true), new List<Account>{ acme });
        Test.stopTest();

        Integration_Failure__c failure = onlyFailure();
        Assert.isTrue(failure.Integration__c.endsWith('RecordErpNumbers'), failure.Integration__c);
        Assert.areEqual(acme.Id, failure.Record_Ids__c);
        Assert.areEqual(400, failure.Status__c);
        Assert.areEqual('{"error":"name missing"}', failure.Reply_Body__c);
        Assert.areEqual('POST /customers failed with status 400 after 1 attempt(s).', failure.Reason__c);
        Assert.isNull([SELECT AccountNumber FROM Account WHERE Id = :acme.Id].AccountNumber);
        Assert.isNull(ForgeIntegration.followOnHeldForTest, '400 is not worth retrying');
    }

    @IsTest
    static void anUnavailableSystemIsRetriedWithTheSameIdempotencyKey()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers')
            .reply(503, 'busy')
            .reply(201, numbers(1));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, true), new List<Account>{ acme });
        Test.stopTest();

        Assert.isNull([SELECT AccountNumber FROM Account WHERE Id = :acme.Id].AccountNumber, 'not saved yet');

        ForgeIntegration.runFollowOnHeldForTest();

        Assert.areEqual('ERP C-1', [SELECT AccountNumber FROM Account WHERE Id = :acme.Id].AccountNumber);
        String firstKey = customers.requests()[0].getHeader('Idempotency-Key');
        Assert.isNotNull(firstKey);
        Assert.areEqual(firstKey, customers.requests()[1].getHeader('Idempotency-Key'), 'a retry repeats the key');
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);
    }

    @IsTest
    static void eachCallHasItsOwnIdempotencyKey()
    {
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(1));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, true), newAccounts(2));
        Test.stopTest();

        Assert.areNotEqual(customers.requests()[0].getHeader('Idempotency-Key'),
            customers.requests()[1].getHeader('Idempotency-Key'));
    }

    @IsTest
    static void retriesUsedUpLeaveOneFailureRecord()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(503, 'busy');

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, true), new List<Account>{ acme });
        Test.stopTest();
        ForgeIntegration.runFollowOnHeldForTest();
        ForgeIntegration.runFollowOnHeldForTest();

        Assert.areEqual(3, customers.requests().size(), 'at most 3 attempts');
        Assert.isNull(ForgeIntegration.followOnHeldForTest);
        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(503, failure.Status__c);
        Assert.areEqual('busy', failure.Reply_Body__c);
        Assert.areEqual('POST /customers failed with status 503 after 3 attempt(s).', failure.Reason__c);
    }

    @IsTest
    static void aPostIsNotRetriedUnlessRepeatsAreSafe()
    {
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(503, 'busy');

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, false), newAccounts(1));
        Test.stopTest();

        Assert.areEqual(1, customers.requests().size());
        Assert.isNull(ForgeIntegration.followOnHeldForTest, 'the ERP may have acted on the lost reply');
        Assert.areEqual('POST /customers failed with status 503 after 1 attempt(s); not retried, because the call had sent'
            + ' a POST, which the integration does not say may be repeated.', onlyFailure().Reason__c);
    }

    @IsTest
    static void aCallThatSentAPostIsNotRetriedWhenALaterGetIsUnavailable()
    {
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(201, 'C-1');
        ForgeHttpMock.connection(ERP).get('/credit-limits').reply(503, 'busy');

        Test.startTest();
        ForgeIntegration.start(new CreateCustomersWithCreditLimits(false), newAccounts(1));
        Test.stopTest();

        Assert.isNull(ForgeIntegration.followOnHeldForTest, 'repeating the call would post the customer again');
        Assert.areEqual(1, customers.requests().size());
        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(503, failure.Status__c);
        Assert.isTrue(failure.Reason__c.contains('not retried, because the call had sent a POST'), failure.Reason__c);
    }

    @IsTest
    static void aCallThatSentAPostIsRetriedWholeWhenRepeatsAreSafe()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(201, 'C-1');
        ForgeHttpMock.connection(ERP).get('/credit-limits').reply(503, 'busy').reply(200, '5000');

        Test.startTest();
        ForgeIntegration.start(new CreateCustomersWithCreditLimits(true), new List<Account>{ acme });
        Test.stopTest();
        ForgeIntegration.runFollowOnHeldForTest();

        Assert.areEqual(2, customers.requests().size(), 'the retry repeats the whole call, the POST included');
        Assert.areEqual(customers.requests()[0].getHeader('Idempotency-Key'), customers.requests()[1].getHeader('Idempotency-Key'));
        Account saved = [SELECT AccountNumber, AnnualRevenue FROM Account WHERE Id = :acme.Id];
        Assert.areEqual('C-1', saved.AccountNumber);
        Assert.areEqual(5000, saved.AnnualRevenue);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);
    }

    @IsTest
    static void aCallWhoseSecondRequestWouldPassOneHundredCalloutsGoesToTheFollowOnJob()
    {
        List<Account> accounts = newAccounts(50);
        ForgeHttpMock.Route ratings = ForgeHttpMock.connection(ERP).get('/ratings').reply(200, 'Hot');
        ForgeHttpMock.Route limits = ForgeHttpMock.connection(ERP).get('/credit-limits').reply(200, '5000');
        ForgeIntegration.calloutsMadeBeforeJobForTest = 1;

        Test.startTest();
        ForgeIntegration.start(new LookUpRatingsAndLimits(), accounts);
        Test.stopTest();

        Assert.areEqual(50, ratings.requests().size());
        Assert.areEqual(49, limits.requests().size(), 'the last call stops before the 101st callout');
        Assert.areEqual(49, [SELECT COUNT() FROM Account WHERE AnnualRevenue = 5000]);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);

        ForgeIntegration.calloutsMadeBeforeJobForTest = 0;
        ForgeIntegration.runFollowOnHeldForTest();

        Assert.areEqual(51, ratings.requests().size(), 'two GETs may be repeated, so the stopped call is sent again whole');
        Assert.areEqual(50, [SELECT COUNT() FROM Account WHERE Rating = 'Hot' AND AnnualRevenue = 5000]);
    }

    @IsTest
    static void aCallStoppedForRoomAfterAPostBecomesAFailureRecord()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route customers = ForgeHttpMock.connection(ERP).post('/customers').reply(201, 'C-1');
        ForgeHttpMock.Route limits = ForgeHttpMock.connection(ERP).get('/credit-limits').reply(200, '5000');
        ForgeIntegration.calloutsMadeBeforeJobForTest = 99;

        Test.startTest();
        ForgeIntegration.start(new CreateCustomersWithCreditLimits(false), new List<Account>{ acme });
        Test.stopTest();

        Assert.areEqual(1, customers.requests().size());
        Assert.areEqual(0, limits.requests().size());
        Assert.isNull(ForgeIntegration.followOnHeldForTest, 'the POST is not sent a second time');
        Assert.isNull([SELECT AccountNumber FROM Account WHERE Id = :acme.Id].AccountNumber);
        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(201, failure.Status__c);
        Assert.areEqual('C-1', failure.Reply_Body__c, 'the reply of the POST is kept');
        Assert.isTrue(failure.Reason__c.startsWith('Not finished: the job ran out of callout room after the call had sent a POST'), failure.Reason__c);
    }

    @IsTest
    static void aRequestWaitingLongerThanTheSecondsLeftIsNotSent()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route ratings = ForgeHttpMock.connection(ERP).get('/ratings').reply(200, 'Hot');
        ForgeIntegration.secondsWaitedBeforeJobForTest = 80;

        Test.startTest();
        ForgeIntegration.start(new LookUpSlowRatings(60), new List<Account>{ acme });
        Test.stopTest();

        Assert.areEqual(0, ratings.requests().size(), '40 seconds are left and the request may wait 60');
        Assert.isNotNull(ForgeIntegration.followOnHeldForTest);

        ForgeIntegration.secondsWaitedBeforeJobForTest = 0;
        ForgeIntegration.runFollowOnHeldForTest();

        Assert.areEqual('Hot', [SELECT Rating FROM Account WHERE Id = :acme.Id].Rating);
    }

    @IsTest
    static void aRequestWaitingNoLongerThanTheSecondsLeftIsSent()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.connection(ERP).get('/ratings').reply(200, 'Hot');
        ForgeIntegration.secondsWaitedBeforeJobForTest = 80;

        Test.startTest();
        ForgeIntegration.start(new LookUpSlowRatings(30), new List<Account>{ acme });
        Test.stopTest();

        Assert.areEqual('Hot', [SELECT Rating FROM Account WHERE Id = :acme.Id].Rating);
        Assert.isNull(ForgeIntegration.followOnHeldForTest);
    }

    @IsTest
    static void anAfterCallsThatThrowsIsUndoneAndTheSavedRecordsAndTheRetryStay()
    {
        List<Account> accounts = newAccounts(2);
        ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(1)).reply(503, 'busy');

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbersButFailToWelcome(), accounts);
        Test.stopTest();

        Assert.areEqual('ERP C-1', [SELECT AccountNumber FROM Account WHERE Id = :accounts[0].Id].AccountNumber);
        Assert.areEqual(0, [SELECT COUNT() FROM Task], 'the welcome afterCalls inserted is undone');
        Assert.isNotNull(ForgeIntegration.followOnHeldForTest, 'the second call is still retried');
        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(accounts[0].Id + ',' + accounts[1].Id, failure.Record_Ids__c, 'the job\'s records');
        Assert.isTrue(failure.Reason__c.startsWith('afterCalls failed'), failure.Reason__c);
        Assert.isTrue(failure.Reason__c.endsWith('System.DmlException: Welcome tasks are closed today'), failure.Reason__c);
    }

    @IsTest
    static void aRetryTheJobCanNoLongerQueueBecomesAFailureRecord()
    {
        List<Account> accounts = newAccounts(2);
        ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(1)).reply(503, 'busy');
        // A test cannot chain a job from a queued job, so the first job only passes the calls on, and the
        // follow-on runs here, where afterCalls can use up the jobs the transaction may queue.
        ForgeIntegration.calloutsMadeBeforeJobForTest = 100;
        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbersAndQueueEveryJob(), accounts);
        Test.stopTest();
        ForgeIntegration.calloutsMadeBeforeJobForTest = 0;

        ForgeIntegration.runFollowOnHeldForTest();

        Assert.isNull(ForgeIntegration.followOnHeldForTest);
        Assert.areEqual('ERP C-1', [SELECT AccountNumber FROM Account WHERE Id = :accounts[0].Id].AccountNumber);
        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(accounts[1].Id, failure.Record_Ids__c);
        Assert.areEqual('Not sent: the job had already queued the one job it may, so the call could not be passed to a'
            + ' follow-on job.', failure.Reason__c);
    }

    @IsTest
    static void aTimedOutGetIsRetriedWithoutBeingTold()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.connection(ERP).get('/ratings/' + acme.Id).timesOut().reply(200, 'Hot');

        Test.startTest();
        ForgeIntegration.start(new LookUpCreditRatings(), new List<Account>{ acme });
        Test.stopTest();
        ForgeIntegration.runFollowOnHeldForTest();

        Assert.areEqual('Hot', [SELECT Rating FROM Account WHERE Id = :acme.Id].Rating);
    }

    @IsTest
    static void aRecordThatFailsToSaveKeepsItsReplyAndTheOthersAreSaved()
    {
        Account good = new Account(Name = 'Good customer');
        Account broken = new Account(Name = 'Broken customer');
        insert new List<Account>{ good, broken };
        ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(1));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, false), new List<Account>{ good, broken });
        Test.stopTest();

        Assert.areEqual('ERP C-1', [SELECT AccountNumber FROM Account WHERE Id = :good.Id].AccountNumber);
        Assert.isNull([SELECT AccountNumber FROM Account WHERE Id = :broken.Id].AccountNumber);
        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(broken.Id, failure.Record_Ids__c);
        Assert.isTrue(failure.Reply_Body__c.contains('"AccountNumber":"ERP C-1"'), failure.Reply_Body__c);
        Assert.isTrue(failure.Reason__c.startsWith('The reply arrived but the record could not be saved: '), failure.Reason__c);
        Assert.areEqual(1, [SELECT COUNT() FROM Task], 'afterCalls gets only the records that saved');
    }

    @IsTest
    static void aCallWhoseRunThrowsIsNotRetried()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route ratings = ForgeHttpMock.connection(ERP).get('/ratings/' + acme.Id).reply(200, '["Hot"]');

        Test.startTest();
        ForgeIntegration.start(new ReadCreditRatingsFromJson(), new List<Account>{ acme });
        Test.stopTest();

        Assert.areEqual(1, ratings.requests().size(), 'a GET is retried after a 503, but not after an error in run');
        Assert.isNull(ForgeIntegration.followOnHeldForTest);
        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(200, failure.Status__c);
        Assert.areEqual('["Hot"]', failure.Reply_Body__c);
        Assert.isTrue(failure.Reason__c.startsWith('The integration failed while handling the reply: System.TypeException: '), failure.Reason__c);
    }

    @IsTest
    static void aCallWhoseRunThrowsSavesNoneOfItsChanges()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.connection(ERP).get('/ratings/' + acme.Id).reply(200, '["Hot"]');

        Test.startTest();
        ForgeIntegration.start(new ReadCreditRatingsFromJson(), new List<Account>{ acme });
        Test.stopTest();

        Account saved = [SELECT Description, Rating FROM Account WHERE Id = :acme.Id];
        Assert.isNull(saved.Description, 'run set it before the error, and it is discarded');
        Assert.isNull(saved.Rating);
        Assert.areEqual(acme.Id, onlyFailure().Record_Ids__c);
    }

    @IsTest
    static void theCallsAfterOneWhoseRunThrowsStillCallOutAndAreSaved()
    {
        List<Account> accounts = newAccounts(2);
        Account unreadable = accounts[0];
        Account readable = accounts[1];
        ForgeHttpMock.connection(ERP).get('/ratings/' + unreadable.Id).reply(200, '["Hot"]');
        ForgeHttpMock.Route laterCall = ForgeHttpMock.connection(ERP).get('/ratings/' + readable.Id).reply(200, '{"rating":"Hot"}');

        Test.startTest();
        ForgeIntegration.start(new ReadCreditRatingsFromJson(), accounts);
        Test.stopTest();

        // Had the failure record been written before the later callout, Salesforce would have refused that callout.
        Assert.areEqual(1, laterCall.requests().size());
        Assert.areEqual('Hot', [SELECT Rating FROM Account WHERE Id = :readable.Id].Rating);
        Assert.areEqual(unreadable.Id, onlyFailure().Record_Ids__c);
    }

    @IsTest
    static void aRecordStartedTwiceIsSentOnce()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.Route ratings = ForgeHttpMock.connection(ERP).get('/ratings/' + acme.Id).reply(200, '{"rating":"Hot"}');

        Test.startTest();
        ForgeIntegration.start(new ReadCreditRatingsFromJson(), new List<Account>{ acme, acme });
        Test.stopTest();

        Assert.areEqual(1, ratings.requests().size());
        Assert.areEqual('Hot', [SELECT Rating FROM Account WHERE Id = :acme.Id].Rating);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);
    }

    @IsTest
    static void aRecordDeletedBeforeTheJobRunsBecomesAFailureRecord()
    {
        Account gone = newAccounts(1)[0];
        ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(1));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, false), new List<Account>{ gone });
        delete gone;
        Test.stopTest();

        Integration_Failure__c failure = onlyFailure();
        Assert.areEqual(gone.Id, failure.Record_Ids__c);
        Assert.isNull(failure.Status__c);
        Assert.isTrue(failure.Reason__c.contains('deleted'), failure.Reason__c);
    }

    @IsTest
    static void eachRecordDeletedBeforeTheJobRunsHasItsOwnFailureRecord()
    {
        List<Account> gone = newAccounts(2);
        ForgeHttpMock.connection(ERP).post('/customers').reply(201, numbers(2));

        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(2, false), gone);
        delete gone;
        Test.stopTest();

        Set<String> failedIds = new Set<String>();
        for (Integration_Failure__c failure : [SELECT Record_Ids__c FROM Integration_Failure__c]) { failedIds.add(failure.Record_Ids__c); }
        Assert.areEqual(new Set<String>{ gone[0].Id, gone[1].Id }, failedIds);
    }

    @IsTest
    static void aStartInATransactionThatMayQueueNoMoreJobsIsRefused()
    {
        List<Account> accounts = newAccounts(1);
        String refusal;

        Test.startTest();
        for (Integer i = 0; i < Limits.getLimitQueueableJobs(); i++) { System.enqueueJob(new DoNothing()); }
        try
        {
            ForgeIntegration.start(new RecordErpNumbers(1, false), accounts);
        }
        catch (ForgeIntegration.StartRefusedException refused)
        {
            refusal = refused.getMessage();
        }
        Test.stopTest();

        Assert.isNotNull(refusal, 'a start with no job left to queue is refused');
        Assert.isTrue(refusal.contains('may queue only'), refusal);
    }

    @IsTest
    static void aRecordNotSavedYetIsRefused()
    {
        try
        {
            ForgeIntegration.start(new RecordErpNumbers(1, false), new List<Account>{ new Account(Name = 'New') });
            Assert.fail('a record without an Id cannot be sent');
        }
        catch (ForgeIntegration.StartRefusedException refused)
        {
            Assert.isTrue(refused.getMessage().contains('not saved yet'), refused.getMessage());
        }
    }

    @IsTest
    static void startingWithNoRecordsQueuesNothing()
    {
        Test.startTest();
        ForgeIntegration.start(new RecordErpNumbers(1, false), new List<Account>());
        Assert.areEqual(0, Limits.getQueueableJobs());
        Test.stopTest();
    }

    @IsTest
    static void aRequestNoTestDescribedFailsTheTestWithTheRequest()
    {
        Account acme = newAccounts(1)[0];
        ForgeHttpMock.connection(ERP);
        Exception raised;

        Test.startTest();
        ForgeIntegration.start(new AskSomethingUndescribed(), new List<Account>{ acme });
        try
        {
            Test.stopTest();
        }
        catch (Exception unmatched)
        {
            raised = unmatched;
        }

        Assert.isNotNull(raised, 'an undescribed request fails the test');
        Assert.isTrue(raised.getMessage().contains('GET callout:ForgeTestErp/nobody-described-this'), raised.getMessage());
    }

    private static List<Account> newAccounts(Integer count)
    {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) { accounts.add(new Account(Name = 'Customer ' + i)); }
        insert accounts;
        return accounts;
    }

    private static String numbers(Integer count)
    {
        List<Map<String, String>> replies = new List<Map<String, String>>();
        for (Integer i = 1; i <= count; i++) { replies.add(new Map<String, String>{ 'customerNumber' => 'C-' + i }); }
        return JSON.serialize(replies);
    }

    private static Integration_Failure__c onlyFailure()
    {
        List<Integration_Failure__c> failures = [
            SELECT Integration__c, Record_Ids__c, Status__c, Reply_Body__c, Reason__c FROM Integration_Failure__c
        ];
        Assert.areEqual(1, failures.size(), String.valueOf(failures));
        return failures[0];
    }
}
