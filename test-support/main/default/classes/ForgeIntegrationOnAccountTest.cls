/**
 * This file is part of the Forge Platform project
 *
 * Test support only: the ForgeHttp scenario as a developer meets it, with
 * SendCustomersToErp started from an Account trigger handler, run as a Standard
 * User, and the ERP number kept on Account.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
@IsTest
private class ForgeIntegrationOnAccountTest
{

    private static Integer accountUpdates = 0;

    /** Counts the Account updates, as any other trigger logic on the object would see them. */
    private class AccountUpdatesCounted extends ForgeTriggerHandler
    {
        protected override void onTrigger(ForgeTriggerContext ctx)
        {
            if (ctx.operationType == System.TriggerOperation.AFTER_UPDATE) { accountUpdates++; }
        }
    }

    /** Starts the ERP integration on every insert and every update, so its own save would start it again. */
    private class SendEveryChangeToErp extends ForgeTriggerHandler
    {
        protected override void onTrigger(ForgeTriggerContext ctx)
        {
            ForgeIntegration.start(new SendCustomersToErp(), ctx.newRecords);
        }
    }

    /** The ERP integration for a number users may not edit: it saves in system mode. */
    private class SendCustomersToErpAsSystem extends ForgeIntegration
    {
        protected override void run(List<SObject> records)
        {
            Account account = (Account) records[0];
            List<ErpCustomerNumber> numbers = (List<ErpCustomerNumber>) connection('ERP')
                .post('/customers', ErpCustomer.fromAccounts(new List<Account>{ account }))
                .readAs(List<ErpCustomerNumber>.class);
            account.Erp_Customer_Number__c = numbers[0].customerNumber;
        }

        protected override AccessLevel accessLevel() { return AccessLevel.SYSTEM_MODE; }
    }

    /** Reads a credit rating; it changes Rating and nothing else. */
    private class LookUpCreditRating extends ForgeIntegration
    {
        protected override void run(List<SObject> records)
        {
            Account account = (Account) records[0];
            account.Rating = connection('ERP').get('/ratings/' + account.Id).body;
        }
    }

    @IsTest
    static void newCustomersGetTheirErpNumber()
    {
        ForgeTestAccountHandlers.toRun = new List<ForgeTriggerHandler>{ new NewAccountsBecomeErpCustomers() };
        ForgeHttpMock.connection('ERP').post('/customers')
            .reply(201, '[{"customerNumber":"C-1001"}]');

        System.runAs(salesUser('Forge_Test_Erp_Customer_Number'))
        {
            Test.startTest();
            insert new Account(Name = 'Acme Ltd');
            Test.stopTest();
        }

        Assert.areEqual('C-1001', [SELECT Erp_Customer_Number__c FROM Account].Erp_Customer_Number__c);
    }

    @IsTest
    static void twoThousandNewAccountsMakeTenJobsOfFourCallsAndTenSaves()
    {
        ForgeTestAccountHandlers.toRun = new List<ForgeTriggerHandler>{
            new NewAccountsBecomeErpCustomers(), new AccountUpdatesCounted()
        };
        ForgeHttpMock.Route customers = ForgeHttpMock.connection('ERP').post('/customers').reply(201, numbers(50));

        System.runAs(salesUser('Forge_Test_Erp_Customer_Number'))
        {
            Test.startTest();
            insert newAccounts(2000);
            Test.stopTest();
        }

        Assert.areEqual(10, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable'], 'one job per trigger chunk');
        Assert.areEqual(40, customers.requests().size(), '4 calls of 50 in each job');
        Assert.areEqual(10, accountUpdates, 'each job saves its 200 Accounts in one update');
        Assert.areEqual(2000, [SELECT COUNT() FROM Account WHERE Erp_Customer_Number__c != null]);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);
    }

    @IsTest
    static void bypassingTheHandlerStartsNoIntegration()
    {
        ForgeTestAccountHandlers.toRun = new List<ForgeTriggerHandler>{ new NewAccountsBecomeErpCustomers() };
        ForgeHttpMock.Route customers = ForgeHttpMock.connection('ERP').post('/customers').reply(201, numbers(1));

        System.runAs(salesUser('Forge_Test_Erp_Customer_Number'))
        {
            Test.startTest();
            ForgeTriggerHandler.bypass('NewAccountsBecomeErpCustomers');
            insert new Account(Name = 'Acme Ltd');
            Test.stopTest();
        }

        Assert.areEqual(0, customers.requests().size());
        Assert.areEqual(0, [SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'Queueable']);
    }

    @IsTest
    static void savingTheReplyDoesNotStartTheIntegrationAgainButOtherTriggerLogicRuns()
    {
        ForgeTestAccountHandlers.toRun = new List<ForgeTriggerHandler>{
            new SendEveryChangeToErp(), new AccountUpdatesCounted()
        };
        ForgeHttpMock.Route customers = ForgeHttpMock.connection('ERP').post('/customers').reply(201, numbers(1));

        System.runAs(salesUser('Forge_Test_Erp_Customer_Number'))
        {
            Test.startTest();
            insert new Account(Name = 'Acme Ltd');
            Test.stopTest();
        }

        Assert.areEqual(1, customers.requests().size());
        Assert.areEqual(1, accountUpdates, 'the Account trigger ran for the save');
        Assert.isNull(ForgeIntegration.followOnHeldForTest);
        Assert.areEqual('C-1', [SELECT Erp_Customer_Number__c FROM Account].Erp_Customer_Number__c);
    }

    @IsTest
    static void aUserWhoCannotEditTheNumberGetsAFailureRecordHoldingIt()
    {
        ForgeTestAccountHandlers.toRun = new List<ForgeTriggerHandler>{ new NewAccountsBecomeErpCustomers() };
        ForgeHttpMock.connection('ERP').post('/customers').reply(201, '[{"customerNumber":"C-1001"}]');

        System.runAs(salesUser(null))
        {
            Test.startTest();
            insert new Account(Name = 'Acme Ltd');
            Test.stopTest();
        }

        Assert.isNull([SELECT Erp_Customer_Number__c FROM Account].Erp_Customer_Number__c);
        Integration_Failure__c failure = [SELECT Reply_Body__c, Reason__c FROM Integration_Failure__c];
        Assert.isTrue(failure.Reply_Body__c.contains('C-1001'), 'the ERP\'s answer is kept: ' + failure.Reply_Body__c);
    }

    @IsTest
    static void anIntegrationInSystemModeSavesANumberTheUserCannotEdit()
    {
        ForgeHttpMock.connection('ERP').post('/customers').reply(201, '[{"customerNumber":"C-1001"}]');

        System.runAs(salesUser(null))
        {
            Account acme = new Account(Name = 'Acme Ltd');
            insert acme;
            Test.startTest();
            ForgeIntegration.start(new SendCustomersToErpAsSystem(), new List<Account>{ acme });
            Test.stopTest();
        }

        Assert.areEqual('C-1001', [SELECT Erp_Customer_Number__c FROM Account].Erp_Customer_Number__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);
    }

    @IsTest
    static void onlyTheFieldsACallChangedAreSaved()
    {
        Account acme = new Account(Name = 'Acme Ltd', Erp_Customer_Number__c = 'C-1001');
        insert acme;
        ForgeHttpMock.connection('ERP').get('/ratings/' + acme.Id).reply(200, 'Warm');

        System.runAs(salesUser('Forge_Test_Erp_Customer_Number_Read'))
        {
            Account whole = [SELECT Id, Name, Erp_Customer_Number__c FROM Account WHERE Id = :acme.Id];
            Assert.isFalse(Database.update(whole, false, AccessLevel.USER_MODE).isSuccess(),
                'precondition: saving the whole record would fail, since this user may only read the ERP number');

            Test.startTest();
            ForgeIntegration.start(new LookUpCreditRating(), new List<Account>{ acme });
            Test.stopTest();
        }

        Account saved = [SELECT Rating, Erp_Customer_Number__c FROM Account WHERE Id = :acme.Id];
        Assert.areEqual('Warm', saved.Rating);
        Assert.areEqual('C-1001', saved.Erp_Customer_Number__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Integration_Failure__c]);
    }

    private static User salesUser(String permissionSetName)
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
        // Setup records go in their own runAs, so a test may insert Accounts before it.
        System.runAs(new User(Id = UserInfo.getUserId()))
        {
            insert seller;
            if (permissionSetName != null)
            {
                Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName].Id;
                insert new PermissionSetAssignment(AssigneeId = seller.Id, PermissionSetId = permissionSetId);
            }
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
