/**
 * Benchmarks ForgeAccess the way the open-opportunities table uses it: a sales rep, a
 * Standard User with the Forge_Test_Access permission set, reads an account's open
 * opportunities, changes their stage and saves them in the same transaction. The same
 * work is measured in plain Apex with the same checks written by hand, and both are
 * measured again saving records that hold only an Id and the changed stage, as the
 * table sends them. The two controllers below are the ones in
 * perf/scenarios/user-access. It is a test class because only a test can run as
 * another user; each method writes one measurement line for the runner.
 */
@IsTest
private class ForgeAccessBenchmark
{
    private static final String NEW_STAGE = 'Negotiation/Review';

    @IsTest
    static void oneOpportunityWithForgeAccess()
    {
        readChangeAndSave(1, new WithForgeAccess(), null);
    }

    @IsTest
    static void twoHundredOpportunitiesWithForgeAccess()
    {
        readChangeAndSave(200, new WithForgeAccess(), null);
    }

    @IsTest
    static void twoThousandOpportunitiesWithForgeAccess()
    {
        readChangeAndSave(2000, new WithForgeAccess(), null);
    }

    @IsTest
    static void oneOpportunityInPlainApex()
    {
        readChangeAndSave(1, new InPlainApex(), 'plain');
    }

    @IsTest
    static void twoHundredOpportunitiesInPlainApex()
    {
        readChangeAndSave(200, new InPlainApex(), 'plain');
    }

    @IsTest
    static void twoThousandOpportunitiesInPlainApex()
    {
        readChangeAndSave(2000, new InPlainApex(), 'plain');
    }

    @IsTest
    static void oneTableSaveWithForgeAccess()
    {
        saveAsTheTableSends(1, new WithForgeAccess(), 'table-save');
    }

    @IsTest
    static void twoHundredTableSavesWithForgeAccess()
    {
        saveAsTheTableSends(200, new WithForgeAccess(), 'table-save');
    }

    @IsTest
    static void twoThousandTableSavesWithForgeAccess()
    {
        saveAsTheTableSends(2000, new WithForgeAccess(), 'table-save');
    }

    @IsTest
    static void oneTableSaveInPlainApex()
    {
        saveAsTheTableSends(1, new InPlainApex(), 'plain-table-save');
    }

    @IsTest
    static void twoHundredTableSavesInPlainApex()
    {
        saveAsTheTableSends(200, new InPlainApex(), 'plain-table-save');
    }

    @IsTest
    static void twoThousandTableSavesInPlainApex()
    {
        saveAsTheTableSends(2000, new InPlainApex(), 'plain-table-save');
    }

    /** What the table's controller does: read an account's open opportunities, and save the ones the rep changed. */
    private interface OpenOpportunities
    {
        List<Opportunity> forAccount(Id accountId);
        void save(List<Opportunity> changes);
    }

    /** The controller in perf/scenarios/user-access/forge.cls. */
    private class WithForgeAccess implements OpenOpportunities
    {
        public List<Opportunity> forAccount(Id accountId)
        {
            return (List<Opportunity>) ForgeAccess.query(
                'SELECT Name, StageName, Amount, CloseDate FROM Opportunity'
                    + ' WHERE AccountId = :accountId AND IsClosed = false',
                new Map<String, Object>{ 'accountId' => accountId }
            );
        }

        public void save(List<Opportunity> changes)
        {
            ForgeAccess.save(changes);
        }
    }

    /** The controller in perf/scenarios/user-access/plain.cls. */
    private class InPlainApex implements OpenOpportunities
    {
        public List<Opportunity> forAccount(Id accountId)
        {
            if (!Schema.SObjectType.Opportunity.isAccessible())
            {
                throw new AccessDeniedException('You cannot read Opportunity.');
            }
            try
            {
                return [
                    SELECT Name, StageName, Amount, CloseDate FROM Opportunity
                    WHERE AccountId = :accountId AND IsClosed = false
                    WITH USER_MODE
                ];
            }
            catch (QueryException failure)
            {
                throw denied('read', failure.getInaccessibleFields());
            }
        }

        public void save(List<Opportunity> changes)
        {
            if (!Schema.SObjectType.Opportunity.isUpdateable())
            {
                throw new AccessDeniedException('You cannot edit Opportunity.');
            }
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, changes);
            if (!decision.getRemovedFields().isEmpty())
            {
                throw denied('edit', decision.getRemovedFields());
            }
            update as user changes;
        }

        private AccessDeniedException denied(String verb, Map<String, Set<String>> fieldsByObject)
        {
            List<String> names = new List<String>();
            for (String objectName : fieldsByObject.keySet())
            {
                for (String fieldName : fieldsByObject.get(objectName))
                {
                    names.add(objectName + '.' + fieldName);
                }
            }
            names.sort();
            Integer more = names.size() - 1;
            String rest = more < 1 ? '' : ' and ' + more + (more == 1 ? ' more field' : ' more fields');
            return new AccessDeniedException('You cannot ' + verb + ' ' + names[0] + rest + '.');
        }
    }

    /** The plain controller's error, an inner class of it in plain.cls. */
    private class AccessDeniedException extends Exception {}

    /** The governor counters and the clock at one moment, so that a measurement is what was spent since. */
    private class Reading
    {
        private final Integer cpuTimeMs = Limits.getCpuTime();
        private final Integer heapBytes = Limits.getHeapSize();
        private final Integer soqlQueries = Limits.getQueries();
        private final Integer queryRows = Limits.getQueryRows();
        private final Integer dmlStatements = Limits.getDmlStatements();
        private final Integer dmlRows = Limits.getDmlRows();
        private final Long startedAt = System.now().getTime();

        public Map<String, Object> spentSince()
        {
            Long wallTimeMs = System.now().getTime() - startedAt;
            return new Map<String, Object>{
                'wallTimeMs' => wallTimeMs,
                'cpuTimeMs' => Limits.getCpuTime() - cpuTimeMs,
                'heapBytes' => Limits.getHeapSize() - heapBytes,
                'soqlQueries' => Limits.getQueries() - soqlQueries,
                'queryRows' => Limits.getQueryRows() - queryRows,
                'dmlStatements' => Limits.getDmlStatements() - dmlStatements,
                'dmlRows' => Limits.getDmlRows() - dmlRows
            };
        }
    }

    /** Measures reading the account's open opportunities, changing only their stage and saving them, in one transaction. */
    private static void readChangeAndSave(Integer records, OpenOpportunities controller, String scenario)
    {
        User rep = aSalesRep();
        Account account = anAccountWithOpenOpportunities(rep, records);
        Map<String, Object> measures;
        System.runAs(rep)
        {
            Test.startTest();
            Reading before = new Reading();
            List<Opportunity> opportunities = controller.forAccount(account.Id);
            for (Opportunity opportunity : opportunities)
            {
                opportunity.StageName = NEW_STAGE;
            }
            controller.save(opportunities);
            measures = before.spentSince();
            Test.stopTest();
        }
        report(records, scenario, measures, account);
    }

    /** Measures saving records that hold only an Id and the changed stage, as the table sends them in a call of its own. */
    private static void saveAsTheTableSends(Integer records, OpenOpportunities controller, String scenario)
    {
        User rep = aSalesRep();
        Account account = anAccountWithOpenOpportunities(rep, records);
        List<Opportunity> changes = new List<Opportunity>();
        for (Opportunity opportunity : [SELECT Id FROM Opportunity WHERE AccountId = :account.Id])
        {
            changes.add(new Opportunity(Id = opportunity.Id, StageName = NEW_STAGE));
        }
        Map<String, Object> measures;
        System.runAs(rep)
        {
            Test.startTest();
            Reading before = new Reading();
            controller.save(changes);
            measures = before.spentSince();
            Test.stopTest();
        }
        report(records, scenario, measures, account);
    }

    private static void report(Integer records, String scenario, Map<String, Object> measures, Account account)
    {
        measures.put('module', 'user-access');
        measures.put('records', records);
        if (scenario != null)
        {
            measures.put('scenario', scenario);
        }
        measures.put('recordsHandled', [SELECT COUNT() FROM Opportunity WHERE AccountId = :account.Id AND StageName = :NEW_STAGE]);
        System.debug(LoggingLevel.ERROR, ForgeBenchmark.REPORT_PREFIX + JSON.serialize(measures));
        Assert.areEqual(records, measures.get('recordsHandled'), 'every opportunity is saved in its new stage');
    }

    private static User aSalesRep()
    {
        User rep = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            LastName = 'Rep',
            Alias = 'rep',
            Email = 'rep@forge.example.com',
            Username = 'rep' + System.currentTimeMillis() + '@forge.example.com',
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId()))
        {
            insert rep;
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Forge_Test_Access'].Id;
            insert new PermissionSetAssignment(AssigneeId = rep.Id, PermissionSetId = permissionSetId);
        }
        return rep;
    }

    private static Account anAccountWithOpenOpportunities(User owner, Integer count)
    {
        Account account = new Account(Name = 'Customer', OwnerId = owner.Id);
        insert account;
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < count; i++)
        {
            opportunities.add(new Opportunity(
                Name = 'Deal ' + i,
                AccountId = account.Id,
                StageName = 'Prospecting',
                Amount = 1000,
                CloseDate = Date.today().addDays(30),
                OwnerId = owner.Id
            ));
        }
        insert opportunities;
        return account;
    }
}
