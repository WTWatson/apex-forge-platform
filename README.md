# Apex Forge Platform

Apex Forge is a set of Apex classes for Salesforce that handles the repetitive parts
of an org's code, so the code you write is your business logic and nothing else.
You write what should happen to your records. The platform runs it from the
trigger, builds the test data, makes the callouts, retries them and records what
failed.

Every module is measured. Its numbers ship with it in
[docs/performance](docs/performance/README.md), so you can see what it costs before
you use it.

## What it gives you

### Trigger handler

One trigger per object, with no logic in it. You write a handler class that says
what to do with the records; the platform runs it, stops it from running inside
itself by accident, and lets you switch it off for a transaction.

```apex
public with sharing class LeadRatingHandler extends ForgeTriggerHandler {
  private static final Decimal HOT_REVENUE = 1000000;

  protected override void onTrigger(ForgeTriggerContext ctx) {
    for (Lead prospect : (List<Lead>) ctx.newRecords) {
      if (ctx.hasChanged(prospect, Lead.AnnualRevenue)) {
        prospect.Rating = prospect.AnnualRevenue >= HOT_REVENUE ? 'Hot' : 'Warm';
      }
    }
  }
}
```

The trigger is one line:

```apex
trigger LeadTrigger on Lead(before insert, before update) {
  ForgeTriggerDispatcher.run(new LeadRatingHandler());
}
```

- Several handlers on one object run in the order you list them:
  `ForgeTriggerDispatcher.run(new List<ForgeTriggerHandler>{ first, second })`.
- `ForgeTriggerHandler.bypass('LeadRatingHandler')` switches a handler off for the
  rest of the transaction, and `clearBypass` switches it back on.
- In a test, `ForgeTriggerContext.forInsert(records)` and its siblings let you run a
  handler without a trigger.

### Data builder and seeder

Test records for any object without writing a factory class for each one. The
builder fills required fields with placeholder values, builds as many records as
you ask for, and inserts them. The seeder supplies realistic names, emails,
addresses and numbers.

```apex
Account customer = (Account) ForgeDataBuilder.of(Account.SObjectType).persist();

List<SObject> contacts = ForgeDataBuilder.of(Contact.SObjectType)
  .parent(Contact.AccountId, customer)
  .with(Contact.FirstName, ForgeDataSeeder.firstNames())
  .with(Contact.LastName, ForgeDataSeeder.lastNames())
  .with(Contact.Email, ForgeDataSeeder.emails())
  .count(200)
  .persistList();
```

`build()` and `buildList()` return the records without inserting them.

### ForgeHttp: sending records to another system

You say which records go and what the reply changes on them. The platform calls
the Named Credential, moves the work out of the trigger into background jobs,
splits the records into calls, retries calls that are safe to repeat, saves the
fields you changed and records every call that fails. Here new Accounts become
customers in an ERP and keep the customer number it gives them:

```apex
public with sharing class SendCustomersToErp extends ForgeIntegration {
  protected override void run(List<SObject> records) {
    List<Account> accounts = (List<Account>) records;
    List<ErpCustomerNumber> numbers = (List<ErpCustomerNumber>) connection('ERP')
      .post('/customers', ErpCustomer.fromAccounts(accounts))
      .readAs(List<ErpCustomerNumber>.class);
    for (Integer i = 0; i < accounts.size(); i++) {
      accounts[i].Erp_Customer_Number__c = numbers[i].customerNumber;
    }
  }

  protected override Integer recordsPerCall() { return 50; }

  protected override Boolean repeatsAreSafe() { return true; }
}
```

`ErpCustomer` and `ErpCustomerNumber` are two small classes shaped like the ERP's
JSON. A trigger handler starts the integration with
`ForgeIntegration.start(new SendCustomersToErp(), ctx.newRecords);`. A test
describes the ERP's reply in one line:

```apex
ForgeHttpMock.connection('ERP').post('/customers').reply(201, '[{"customerNumber":"C-1001"}]');
```

- It runs as the user who started it, in user mode, unless the integration
  overrides `accessLevel()`.
- A call that fails becomes an `Integration_Failure__c` record with the reason,
  the record Ids and the last reply. The permission set `Forge_Integration_Failures`
  lets an admin read them.
- To call another system directly, outside a trigger,
  `ForgeHttp.connection('ERP').get('/customers/C-1001')` returns the reply.

The full samples, with their tests and the same task written in plain Apex for
comparison, are in [perf/scenarios](perf/scenarios). The design behind ForgeHttp
is in [docs/design/forge-http.md](docs/design/forge-http.md).

## Install it in your org

The platform is source code, not a managed package. You need the
[Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) and an org
you have logged in to with it.

```bash
git clone https://github.com/WTWatson/apex-forge-platform.git
cd apex-forge-platform
sf project deploy start --source-dir force-app -o <your-org>
```

`force-app` is everything your org needs. For ForgeHttp, also create a Named
Credential for each system you call; your code refers to it by name.

## Run the tests

The tests need the sample triggers and classes in `test-support`, which your
production org should never receive. Run them in a scratch org or sandbox:

```bash
sf project deploy start --source-dir force-app --source-dir test-support -o <your-scratch-org>
sf apex run test -o <your-scratch-org> --test-level RunLocalTests --code-coverage --wait 20
```

## More

- [AGENTS.md](AGENTS.md): the standards every change follows.
- [ROADMAP.md](ROADMAP.md): what has shipped and what comes next.
- [docs/performance](docs/performance/README.md): what each module costs in CPU
  time, memory, queries and DML, and how it is measured.
