# ForgeHttp: integration callouts without the plumbing

A developer integrating Salesforce with another system should write what the
integration means (which records go where, what the reply changes) and nothing
about building requests, reading status codes, retrying, serialising JSON, getting
the callout out of a trigger, or mocking HTTP in tests.

## The scenario

New Accounts become customers in the company's ERP. When an Account is created, the
ERP must get the customer, and the ERP's customer number must be stored back on the
Account (`Erp_Customer_Number__c`). The ERP is reached through a Named Credential
`ERP`; it accepts `POST /customers` with up to 50 customers per call and answers
with one customer number per customer, in order.

### What the developer writes

The integration:

```apex
/** Sends new customers to the ERP and records the customer number it gives each one. */
public with sharing class SendCustomersToErp extends ForgeIntegration {

    /** Registers each Account as an ERP customer and keeps the number the ERP assigns. */
    protected override void run(List<SObject> records) {
        List<Account> accounts = (List<Account>) records;
        List<ErpCustomerNumber> numbers = (List<ErpCustomerNumber>) connection('ERP')
            .post('/customers', ErpCustomer.fromAccounts(accounts))
            .bodyAs(List<ErpCustomerNumber>.class);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Erp_Customer_Number__c = numbers[i].customerNumber;
        }
    }

    /** The ERP takes at most 50 customers per call. */
    protected override Integer recordsPerCall() { return 50; }
}
```

Starting it from the Account trigger handler (no callout in the trigger; the
platform moves it out of the transaction):

```apex
protected override void onTrigger(ForgeTriggerContext ctx) {
    if (ctx.operationType == System.TriggerOperation.AFTER_INSERT) {
        ForgeIntegration.start(new SendCustomersToErp(), ctx.newRecords);
    }
}
```

The test:

```apex
@IsTest
static void newCustomersGetTheirErpNumber() {
    ForgeHttpMock.on('ERP').post('/customers')
        .reply(201, '[{"customerNumber":"C-1001"}]');

    Test.startTest();
    insert new Account(Name = 'Acme Ltd');
    Test.stopTest();

    Assert.areEqual('C-1001', [SELECT Erp_Customer_Number__c FROM Account].Erp_Customer_Number__c);
}
```

`ErpCustomer` and `ErpCustomerNumber` are the consumer's plain data classes (the
ERP's JSON shape); they are business vocabulary, not plumbing.

### What the developer does not write

`HttpRequest`/`HttpResponse`, endpoint strings with `callout:`, headers, status-code
checks, `JSON.serialize`/`deserialize` calls, a `Queueable` with
`Database.AllowsCallouts`, chunking into 50s and into the 100-callouts-per-job
limit, retry loops, an `HttpCalloutMock` class per test.

## What the platform does underneath

- **`ForgeHttp.Connection`** (`connection('ERP')`): a Named Credential by name; the
  endpoint is `callout:ERP` + path. No URLs, keys or tokens in code. `get`, `post`,
  `put`, `patch`, `deleteAt` (`delete` is reserved in Apex); a body that is not a String is serialised to JSON with
  `Content-Type: application/json`. Default timeout 30 s, settable per connection.
- **`ForgeHttp.Response`**: status, body, headers; `bodyAs(Type)` deserialises the body.
  A non-2xx reply throws `ForgeHttp.CalloutFailure` carrying status, body and the
  request's method and path, unless the consumer asks for the response as is.
- **Retry**: on a timeout or 502/503/504, retried with backoff, across jobs (not by
  spinning in the transaction). Default 3 attempts.
- **`ForgeIntegration`**: the unit a consumer writes.
  - `start(integration, records)` can be called from anywhere: a trigger, a
    service class, an anonymous script.
  - It always queues: it enqueues a Queueable with `Database.AllowsCallouts`
    carrying the record Ids, and the job queries the records again. It never
    calls out in the caller's transaction. In a test, `Test.stopTest()` runs it.
  - The job splits the records into calls of `recordsPerCall()` and into jobs of
    at most 100 callouts.
  - Bulk: 200 Accounts make 4 calls in one job; 2,000 make 40 calls, still one job.
- **Saving what the integration changed**: Apex refuses a callout after
  uncommitted DML in the same transaction, so `run` makes no DML. It changes fields
  on the records it was given; after the job's last call the platform updates those
  records once (one DML for the whole job, so 2,000 Accounts are one update, which
  runs the Account trigger; the platform switches that integration off during its
  own update, so saving the records does not start it again). A consumer who needs
  other DML overrides `afterCalls`, which runs after that save:
  ```apex
  /** Tells the account owners their customers now exist in the ERP. */
  protected override void afterCalls(List<SObject> records) {
      insert ErpWelcomeTask.forEach((List<Account>) records);
  }
  ```
- **`ForgeHttpMock`**: a fluent test double installed with `Test.setMock` behind
  the scenes; routes by connection, method and path; an unmatched request fails the
  test with the request it saw.
- Sharing: `with sharing` throughout; the integration's own DML is the consumer's
  (user mode is their call, as with any DML they write).
- Works with the trigger handler's bypass: bypassing the Account handler also means
  no integration starts.

## How it will be measured

At 1, 200 and 2,000 Accounts with the mock: CPU, heap, SOQL, DML, callouts (new
column for this module), jobs enqueued; consumer lines for the scenario against the
plain-Apex version (trigger + Queueable + request building + chunking + mock).

## Decisions

- **Name**: `ForgeHttp`, matching the casing of `ForgeTriggerHandler` and
  `ForgeDataBuilder`.
- **First version**: the connection, the response, the test mock and
  `ForgeIntegration` (async start, splitting into calls, retry), in one pull request.
  The integration is what removes the boilerplate that hurts most.
- **Authentication**: Named Credentials only. No tokens or headers managed by the
  platform.
- **Failures after the last retry**: each is kept as a small `Integration_Failure__c`
  record (integration, records, status, reply body). A later logging module can
  absorb it.
- **Direction**: outbound callouts only. Inbound REST endpoints are out of scope.
- **Saving results**: the platform saves the changed records once, after the job's
  last call, with an `afterCalls` hook for any other DML. The alternative, one call
  per job, chains jobs and hits the chain-depth limit of 5 in developer and scratch
  orgs.
