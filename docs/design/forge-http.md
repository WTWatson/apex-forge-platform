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
with one customer number per customer, in order. Each customer it receives carries
the Account's Salesforce Id; if the ERP already has a customer with that Id, it
returns the existing number instead of creating a second customer.

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
            .readAs(List<ErpCustomerNumber>.class);
        for (Integer i = 0; i < accounts.size(); i++) {
            accounts[i].Erp_Customer_Number__c = numbers[i].customerNumber;
        }
    }

    /** The ERP takes at most 50 customers per call. */
    protected override Integer recordsPerCall() { return 50; }

    /** The ERP recognises a customer it already has, so a repeated call is safe. */
    protected override Boolean repeatsAreSafe() { return true; }
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
    ForgeHttpMock.connection('ERP').post('/customers')
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
  `put`, `patch` and `remove` (Apex reserves `delete`); a body that is not a String
  is serialised to JSON with
  `Content-Type: application/json`. Default timeout 30 s, settable per connection.
- **`ForgeHttp.Response`**: status, body, headers; `readAs(Type)` deserialises the body.
  A non-2xx reply throws `ForgeHttp.CalloutFailureException` (Apex requires the
  suffix) carrying the method, path, status (null on a timeout) and reply body;
  `isWorthRetrying()` is true for a timeout, 502, 503 or 504. A consumer who wants
  every reply as is asks for it with `connection('ERP').acceptingAnyStatus()`.
- **`ForgeIntegration`**: the unit a consumer writes. `start(integration, records)`
  can be called from a trigger, a service class or an anonymous script. It always
  queues a job (a Queueable with `Database.AllowsCallouts`) and never calls out in
  the caller's transaction. In a test, `Test.stopTest()` runs the job.
- **`ForgeHttpMock`**: a fluent test double installed with `Test.setMock` behind
  the scenes; routes by connection, method and path; an unmatched request fails the
  test with the request it saw. Tests of retries run the follow-on job directly,
  through a hook visible only to tests.
- Sharing: `with sharing` throughout.
- Works with the trigger handler's bypass: bypassing the Account handler also means
  no integration starts.

### One job per start

- Each `start` queues one job with the records' Ids. A job's contents are fixed
  when it is queued, so starts are not combined.
- A trigger receives records in chunks of 200, so inserting 2,000 Accounts starts
  10 jobs. Each makes 4 calls of 50 and saves its own 200 Accounts. When one
  `start` is given more records than 100 calls can carry, its job sends the first
  100 calls and passes the rest to a follow-on job.
- A transaction that is itself asynchronous (a Queueable, a batch `execute`, a
  future method) may queue only one job. There the first `start` queues; a second
  `start` in the same transaction throws `ForgeIntegration.StartRefused`, which
  says why. A batch with a scope of 200 or less starts once per `execute`.

### Inside a job

- **Which fields**: the job queries every field of the object that the running
  user can read. `run` needs no field list. A record that was deleted, or that the
  user can no longer see, is skipped and recorded as a failure.
- **Calls**: the records are split into calls of `recordsPerCall()`. Before each
  call the job checks it still has room: under 100 callouts, and at least the
  connection's timeout left of the 120 seconds a transaction may spend waiting on
  callouts. If not, it stops calling and passes the rest to a follow-on job.
- **Retry**: a timeout or a 502, 503 or 504 reply is retried, at most 3 attempts,
  in a follow-on job queued with a delay of 1, then 5 minutes. A GET, PUT or
  `remove` is retried by default. A POST or PATCH is retried only when the
  integration says `repeatsAreSafe()`, because the other system may have acted on a
  call whose reply was lost. Every call carries an `Idempotency-Key` header that
  stays the same across retries of that call, for systems that honour it.
- **Completed calls are kept**: a call that succeeded is never sent again. After
  the job's last call, the platform saves the changes from every call that
  succeeded, even if a later call failed.
- **Saving only what changed**: Apex refuses a callout after uncommitted DML in the
  same transaction, so `run` makes no DML. The platform compares each record after
  `run` with the record it queried, and updates only the fields `run` changed.
  Another user's edit to a different field during the job is kept; an edit to the
  same field is overwritten. It saves all the job's records in one update with
  partial success allowed. A record that fails to save gets a failure record
  holding the reply for it, so the other system's answer (the customer number) is
  not lost.
- **The trigger on that update**: the update runs the Account trigger. The
  platform switches off only that integration while it saves, so the save does not
  start it again; the object's other trigger logic runs as usual.
- **Other DML**: a consumer who needs more DML overrides `afterCalls`, which runs
  after the save:
  ```apex
  /** Tells the account owners their customers now exist in the ERP. */
  protected override void afterCalls(List<SObject> records) {
      insert ErpWelcomeTask.forEach((List<Account>) records);
  }
  ```
- **Follow-on jobs**: a job queues at most one follow-on, after its save. It
  carries the calls not yet sent and the calls due for retry. If the org's limit on
  chained jobs (5 in developer and scratch orgs) would be passed, the calls not
  sent are recorded as failures instead of being dropped.

### Failures

After the last attempt, or when a call cannot be sent, the platform writes one
`Integration_Failure__c` per call: the integration, the record Ids, the status, the
reply body and the reason. Someone can then put it right or start the integration
again for those records.

### Who it runs as, and what they may see

- The job runs as the user who started it. It reads and saves in user mode, so
  that user's object and field permissions and sharing apply.
- An integration that must write a field users cannot edit (an ERP number is often
  read-only to them) overrides `accessLevel()` to return `AccessLevel.SYSTEM_MODE`.
  The choice is visible in the integration's own class.
- The platform writes failure records in system mode, since they are its own
  record of what went wrong.
- The user who starts an integration needs access to the Named Credential's
  external credential, through a permission set. Without it the call fails and is
  recorded.

## How it will be measured

At 1, 200 and 2,000 Accounts started through the Account trigger, with the mock:
CPU, heap, SOQL, DML, callouts (new column for this module) and jobs queued (10 at
2,000); consumer lines for the scenario against the
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
- **Repeated calls**: a POST or PATCH is retried only when the integration says
  repeats are safe, so a lost reply cannot create a second customer by default.
- **Access**: user mode by default; system mode is an explicit choice in the
  integration's class.
- **Saving results**: each job saves the records it changed once, after its last
  call, with an `afterCalls` hook for any other DML. The alternative, one call
  per job, chains jobs and hits the chain-depth limit of 5 in developer and scratch
  orgs.
