/**
 * Benchmarks ForgeHttp the way a consumer uses it: a sales user inserts Accounts,
 * the Account trigger's handler starts SendCustomersToErp, and ForgeHttpMock answers
 * for the ERP. It is a test class because the mock and the Account test trigger work
 * only in tests; each method writes one measurement line for the runner.
 */
@IsTest
private class ForgeHttpBenchmark
{
    private static final List<Map<String, Object>> jobCosts = new List<Map<String, Object>>();

    @IsTest
    static void oneAccount()
    {
        report(1);
    }

    @IsTest
    static void twoHundredAccounts()
    {
        report(200);
    }

    @IsTest
    static void twoThousandAccounts()
    {
        report(2000);
    }

    /** Records what a job has spent by the time its save runs the Account trigger, the last work a job without failures does. */
    private class JobCostRecorded extends ForgeTriggerHandler
    {
        protected override void onTrigger(ForgeTriggerContext ctx)
        {
            if (ctx.operationType == System.TriggerOperation.AFTER_UPDATE)
            {
                jobCosts.add(new Map<String, Object>{
                    'cpuTimeMs' => Limits.getCpuTime(),
                    'cpuLimitMs' => Limits.getLimitCpuTime(),
                    'heapBytes' => Limits.getHeapSize(),
                    'soqlQueries' => Limits.getQueries(),
                    'queryRows' => Limits.getQueryRows(),
                    'dmlStatements' => Limits.getDmlStatements(),
                    'dmlRows' => Limits.getDmlRows(),
                    'callouts' => Limits.getCallouts(),
                    'records' => ctx.newRecords.size()
                });
            }
        }
    }

    private static void report(Integer records)
    {
        User seller = salesUser();
        List<Account> accounts = newAccounts(records);
        ForgeTestAccountHandlers.toRun = new List<ForgeTriggerHandler>{
            new NewAccountsBecomeErpCustomers(), new JobCostRecorded()
        };
        ForgeHttpMock.connection('ERP').post('/customers').reply(201, numbers(50));

        Map<String, Object> measures = new Map<String, Object>{ 'module' => 'forge-http', 'records' => records };
        System.runAs(seller)
        {
            Test.startTest();
            measures.putAll(measureInsert(accounts));
            Test.stopTest();
            measures.put('jobs', jobCosts);
            measures.put('readableFieldsQuery', measureQueries(new Map<Id, Account>(accounts).keySet()));
        }
        measures.put('recordsHandled', [SELECT COUNT() FROM Account WHERE Erp_Customer_Number__c != NULL]);
        measures.put('failures', [SELECT COUNT() FROM Integration_Failure__c]);

        System.debug(LoggingLevel.ERROR, ForgeBenchmark.REPORT_PREFIX + JSON.serialize(measures));
        Assert.areEqual(records, measures.get('recordsHandled'), 'every Account gets its ERP number');
    }

    private static Map<String, Object> measureInsert(List<Account> accounts)
    {
        Integer cpuBefore = Limits.getCpuTime();
        Integer heapBefore = Limits.getHeapSize();
        Integer queriesBefore = Limits.getQueries();
        Integer queryRowsBefore = Limits.getQueryRows();
        Integer dmlBefore = Limits.getDmlStatements();
        Integer dmlRowsBefore = Limits.getDmlRows();
        Integer calloutsBefore = Limits.getCallouts();
        Integer jobsBefore = Limits.getQueueableJobs();
        Long startedAt = System.now().getTime();

        insert accounts;

        return new Map<String, Object>{
            'wallTimeMs' => System.now().getTime() - startedAt,
            'cpuTimeMs' => Limits.getCpuTime() - cpuBefore,
            'heapBytes' => Limits.getHeapSize() - heapBefore,
            'soqlQueries' => Limits.getQueries() - queriesBefore,
            'queryRows' => Limits.getQueryRows() - queryRowsBefore,
            'dmlStatements' => Limits.getDmlStatements() - dmlBefore,
            'dmlRows' => Limits.getDmlRows() - dmlRowsBefore,
            'callouts' => Limits.getCallouts() - calloutsBefore,
            'jobsQueued' => Limits.getQueueableJobs() - jobsBefore
        };
    }

    /** What a job's read of every readable field costs against reading only the fields run uses, for one job's records. */
    private static Map<String, Object> measureQueries(Set<Id> accountIds)
    {
        List<Id> ids = new List<Id>(accountIds);
        List<Id> oneJob = new List<Id>();
        for (Integer i = 0; i < Math.min(200, ids.size()); i++) { oneJob.add(ids[i]); }

        Integer cpuBefore = Limits.getCpuTime();
        Integer heapBefore = Limits.getHeapSize();
        List<SObject> wide = Database.queryWithBinds(readableFieldsQuery(), new Map<String, Object>{ 'ids' => oneJob }, AccessLevel.USER_MODE);
        Integer wideCpu = Limits.getCpuTime() - cpuBefore;
        Integer wideHeap = Limits.getHeapSize() - heapBefore;

        cpuBefore = Limits.getCpuTime();
        heapBefore = Limits.getHeapSize();
        List<Account> narrow = [SELECT Id, Name, Erp_Customer_Number__c FROM Account WHERE Id IN :oneJob WITH USER_MODE];
        Integer narrowCpu = Limits.getCpuTime() - cpuBefore;
        Integer narrowHeap = Limits.getHeapSize() - heapBefore;

        return new Map<String, Object>{
            'records' => wide.size(),
            'fields' => wide.isEmpty() ? 0 : readableFieldCount(),
            'cpuTimeMs' => wideCpu,
            'heapBytes' => wideHeap,
            'narrowCpuTimeMs' => narrowCpu,
            'narrowHeapBytes' => narrowHeap,
            'narrowRecords' => narrow.size()
        };
    }

    // The same field list ForgeIntegration builds for a job: every Account field the user can read, less address, location and binary fields.
    private static List<String> readableFields()
    {
        List<String> names = new List<String>();
        for (Schema.SObjectField field : Account.SObjectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap().values())
        {
            Schema.DescribeFieldResult describe = field.getDescribe();
            Schema.DisplayType type = describe.getType();
            Boolean compoundOrBinary = type == Schema.DisplayType.ADDRESS || type == Schema.DisplayType.LOCATION
                || type == Schema.DisplayType.BASE64;
            if (!compoundOrBinary && describe.isAccessible()) { names.add(describe.getName()); }
        }
        return names;
    }

    private static Integer readableFieldCount()
    {
        return readableFields().size();
    }

    private static String readableFieldsQuery()
    {
        return 'SELECT ' + String.join(readableFields(), ', ') + ' FROM Account WHERE Id IN :ids';
    }

    private static User salesUser()
    {
        User seller = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            LastName = 'Seller',
            Alias = 'seller',
            Email = 'seller@forge.example.com',
            Username = 'seller' + System.currentTimeMillis() + '@forge.example.com',
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId()))
        {
            insert seller;
            Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Forge_Test_Erp_Customer_Number'].Id;
            insert new PermissionSetAssignment(AssigneeId = seller.Id, PermissionSetId = permissionSetId);
        }
        return seller;
    }

    private static List<Account> newAccounts(Integer count)
    {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++) { accounts.add(new Account(Name = 'Customer ' + i)); }
        return accounts;
    }

    private static String numbers(Integer count)
    {
        List<Map<String, String>> replies = new List<Map<String, String>>();
        for (Integer i = 1; i <= count; i++) { replies.add(new Map<String, String>{ 'customerNumber' => 'C-' + i }); }
        return JSON.serialize(replies);
    }
}
