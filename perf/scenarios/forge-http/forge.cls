/**
 * New Accounts become customers in the ERP, and the ERP's customer number is kept
 * on the Account. Each class below is its own file in an org.
 */

/** Sends Accounts to the ERP once they are inserted. */
public with sharing class NewAccountsBecomeErpCustomers extends ForgeTriggerHandler
{
    protected override void onTrigger(ForgeTriggerContext ctx)
    {
        if (ctx.operationType == System.TriggerOperation.AFTER_INSERT)
        {
            ForgeIntegration.start(new SendCustomersToErp(), ctx.newRecords);
        }
    }
}

/** Sends new customers to the ERP and records the customer number it gives each one. */
public with sharing class SendCustomersToErp extends ForgeIntegration
{
    /** Registers each Account as an ERP customer and keeps the number the ERP assigns. */
    protected override void run(List<SObject> records)
    {
        List<Account> accounts = (List<Account>) records;
        List<ErpCustomerNumber> numbers = (List<ErpCustomerNumber>) connection('ERP')
            .post('/customers', ErpCustomer.fromAccounts(accounts))
            .readAs(List<ErpCustomerNumber>.class);
        for (Integer i = 0; i < accounts.size(); i++)
        {
            accounts[i].Erp_Customer_Number__c = numbers[i].customerNumber;
        }
    }

    /** The ERP takes at most 50 customers per call. */
    protected override Integer recordsPerCall() { return 50; }

    /** The ERP recognises a customer it already has, so a repeated call is safe. */
    protected override Boolean repeatsAreSafe() { return true; }
}

/** A customer as the ERP receives it. */
public with sharing class ErpCustomer
{
    /** The Account's Salesforce Id, by which the ERP recognises a customer it already has. */
    public String salesforceId;

    /** The customer's name. */
    public String name;

    /** The ERP customers for these Accounts, in the same order. */
    public static List<ErpCustomer> fromAccounts(List<Account> accounts)
    {
        List<ErpCustomer> customers = new List<ErpCustomer>();
        for (Account account : accounts)
        {
            ErpCustomer customer = new ErpCustomer();
            customer.salesforceId = account.Id;
            customer.name = account.Name;
            customers.add(customer);
        }
        return customers;
    }
}

/** The number the ERP gave one customer. */
public with sharing class ErpCustomerNumber
{
    /** The ERP's customer number. */
    public String customerNumber;
}

@IsTest
private class SendCustomersToErpTest
{
    // The number is saved in user mode, so the test runs as a seller who may edit it.
    @IsTest
    static void newCustomersGetTheirErpNumber()
    {
        ForgeHttpMock.connection('ERP').post('/customers')
            .reply(201, '[{"customerNumber":"C-1001"}]');
        User seller = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            LastName = 'Seller',
            Alias = 'seller',
            Email = 'seller@example.com',
            Username = 'seller' + System.currentTimeMillis() + '@example.com',
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert seller;
        insert new PermissionSetAssignment(
            AssigneeId = seller.Id,
            PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Forge_Test_Erp_Customer_Number'].Id
        );

        System.runAs(seller)
        {
            Test.startTest();
            insert new Account(Name = 'Acme Ltd');
            Test.stopTest();
        }

        Assert.areEqual('C-1001', [SELECT Erp_Customer_Number__c FROM Account].Erp_Customer_Number__c);
    }
}
