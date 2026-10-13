/**
 * New Accounts become customers in the ERP, and the ERP's customer number is kept
 * on the Account: the same behaviour as forge.cls, in plain Apex. Each class below
 * is its own file in an org. Failures go to Integration_Failure__c, as on the forge
 * side, so both keep the same record of what went wrong.
 */

/** Sends new customers to the ERP and records the customer number it gives each one. */
public with sharing class SendCustomersToErp implements Queueable, Database.AllowsCallouts
{
    private static final Integer CUSTOMERS_PER_CALL = 50;
    private static final Integer MOST_ATTEMPTS = 3;
    private static final Set<Integer> STATUSES_WORTH_RETRYING = new Set<Integer>{ 502, 503, 504 };

    private final List<List<Id>> calls;
    private final List<Integer> attempts;

    /** Queues the ERP calls for these Accounts, 50 customers to a call. */
    public static void start(List<Account> accounts)
    {
        List<List<Id>> calls = new List<List<Id>>();
        List<Integer> attempts = new List<Integer>();
        for (Integer i = 0; i < accounts.size(); i++)
        {
            if (Math.mod(i, CUSTOMERS_PER_CALL) == 0)
            {
                calls.add(new List<Id>());
                attempts.add(1);
            }
            calls[calls.size() - 1].add(accounts[i].Id);
        }
        if (!calls.isEmpty())
        {
            System.enqueueJob(new SendCustomersToErp(calls, attempts));
        }
    }

    private SendCustomersToErp(List<List<Id>> calls, List<Integer> attempts)
    {
        this.calls = calls;
        this.attempts = attempts;
    }

    /** Sends as many calls as one job may, saves the numbers, and passes retries and the rest to a new job. */
    public void execute(QueueableContext context)
    {
        Set<Id> accountIds = new Set<Id>();
        for (List<Id> call : calls)
        {
            accountIds.addAll(call);
        }
        Map<Id, Account> accounts = new Map<Id, Account>(
            [SELECT Id, Name FROM Account WHERE Id IN :accountIds WITH USER_MODE]
        );

        List<Account> numbered = new List<Account>();
        List<Integration_Failure__c> failures = new List<Integration_Failure__c>();
        List<List<Id>> laterCalls = new List<List<Id>>();
        List<Integer> laterAttempts = new List<Integer>();

        for (Integer c = 0; c < calls.size(); c++)
        {
            if (Limits.getCallouts() >= Limits.getLimitCallouts())
            {
                laterCalls.add(calls[c]);
                laterAttempts.add(attempts[c]);
                continue;
            }
            List<Account> customers = new List<Account>();
            for (Id accountId : calls[c])
            {
                if (accounts.containsKey(accountId))
                {
                    customers.add(accounts.get(accountId));
                }
            }
            if (customers.isEmpty())
            {
                continue;
            }

            HttpResponse reply;
            try
            {
                reply = new Http().send(customersRequest(customers, calls[c]));
            }
            catch (CalloutException notAnswered)
            {
                reply = null;
            }
            Integer status = reply == null ? null : reply.getStatusCode();

            if (status != null && status >= 200 && status < 300)
            {
                List<ErpCustomerNumber> numbers = (List<ErpCustomerNumber>) JSON.deserialize(
                    reply.getBody(),
                    List<ErpCustomerNumber>.class
                );
                for (Integer i = 0; i < customers.size(); i++)
                {
                    numbered.add(new Account(Id = customers[i].Id, Erp_Customer_Number__c = numbers[i].customerNumber));
                }
            }
            else if ((status == null || STATUSES_WORTH_RETRYING.contains(status)) && attempts[c] < MOST_ATTEMPTS)
            {
                laterCalls.add(calls[c]);
                laterAttempts.add(attempts[c] + 1);
            }
            else
            {
                failures.add(new Integration_Failure__c(
                    Integration__c = 'SendCustomersToErp',
                    Record_Ids__c = String.join(calls[c], ','),
                    Status__c = status,
                    Reply_Body__c = reply == null ? null : reply.getBody(),
                    Reason__c = 'The ERP did not take the customers after ' + attempts[c] + ' attempt(s).'
                ));
            }
        }

        List<Database.SaveResult> saves = Database.update(numbered, false, AccessLevel.USER_MODE);
        for (Integer i = 0; i < saves.size(); i++)
        {
            if (!saves[i].isSuccess())
            {
                failures.add(new Integration_Failure__c(
                    Integration__c = 'SendCustomersToErp',
                    Record_Ids__c = numbered[i].Id,
                    Reply_Body__c = numbered[i].Erp_Customer_Number__c,
                    Reason__c = 'The customer number could not be saved: ' + saves[i].getErrors()[0].getMessage()
                ));
            }
        }

        if (!laterCalls.isEmpty() && !Test.isRunningTest())
        {
            System.enqueueJob(new SendCustomersToErp(laterCalls, laterAttempts), 1);
        }
        Database.insert(failures, AccessLevel.SYSTEM_MODE);
    }

    private static HttpRequest customersRequest(List<Account> customers, List<Id> callIds)
    {
        HttpRequest request = new HttpRequest();
        request.setMethod('POST');
        request.setEndpoint('callout:ERP/customers');
        request.setTimeout(30000);
        request.setHeader('Content-Type', 'application/json');
        request.setHeader(
            'Idempotency-Key',
            EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(String.join(callIds, ','))))
        );
        request.setBody(JSON.serialize(ErpCustomer.fromAccounts(customers)));
        return request;
    }
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
    private class ErpGivesOneNumber implements HttpCalloutMock
    {
        public HttpResponse respond(HttpRequest request)
        {
            Assert.areEqual('POST', request.getMethod());
            Assert.areEqual('callout:ERP/customers', request.getEndpoint());
            HttpResponse reply = new HttpResponse();
            reply.setStatusCode(201);
            reply.setHeader('Content-Type', 'application/json');
            reply.setBody('[{"customerNumber":"C-1001"}]');
            return reply;
        }
    }

    @IsTest
    static void newCustomersGetTheirErpNumber()
    {
        Test.setMock(HttpCalloutMock.class, new ErpGivesOneNumber());

        Test.startTest();
        insert new Account(Name = 'Acme Ltd');
        Test.stopTest();

        Assert.areEqual('C-1001', [SELECT Erp_Customer_Number__c FROM Account].Erp_Customer_Number__c);
    }
}
