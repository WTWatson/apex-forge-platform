# ForgeAccess: the running user's permissions, checked for you

A developer whose code reads or saves records for a user should write which
records and which fields, and nothing about checking that user's object and field
permissions. The platform checks them before it reads or writes. It runs every
query and every save in user mode, and when a check fails it raises one error
naming the object and the field.

## The scenario

A sales rep opens an account in Lightning and sees its open opportunities in a
table: name, stage, amount and close date. The rep changes stages and amounts in
the table and saves. Some reps may read the amount but not edit it. The table
calls an Apex controller, and that controller must respect the rep's permissions:
read only what the rep may read, and save only what the rep may edit.

### What the developer writes

```apex
/** The open opportunities a sales rep works on an account, read and saved with the rep's permissions. */
public with sharing class OpenOpportunities
{
    /** The account's open opportunities, with the fields the table shows. */
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> forAccount(Id accountId)
    {
        return (List<Opportunity>) ForgeAccess.query(
            'SELECT Name, StageName, Amount, CloseDate FROM Opportunity'
                + ' WHERE AccountId = :accountId AND IsClosed = false',
            new Map<String, Object>{ 'accountId' => accountId }
        );
    }

    /** Saves the stages and amounts the rep changed in the table. */
    @AuraEnabled
    public static void save(List<Opportunity> changes)
    {
        ForgeAccess.save(changes);
    }
}
```

The table sends back only what the rep changed: each record holds its Id and the
changed fields, as a `lightning-datatable`'s draft values do. If the rep may not
read `Amount`, `forAccount` raises `ForgeAccess.AccessDeniedException` with the
message "You cannot read Opportunity.Amount." If the rep may read it but not edit
it and changed it, `save` raises "You cannot edit Opportunity.Amount." and saves
nothing. In both cases the table shows that message as it is.

A developer who would rather save what the user may edit and leave out the rest
asks for it in the same line:

```apex
ForgeAccess.leavingOutUneditable().save(changes);
```

The cast on `query` is there because Apex has no generic methods: a method that
returns a list of any object returns `List<SObject>`. The list it returns is a
`List<Opportunity>` underneath, so the cast always holds. The build proves this
with a compile and a test before the sample is final.

A test of the controller runs it as a user with the permission set it needs, as
any user-mode test does. The platform adds no test setup of its own.

### What the developer does not write

- An object check (`isAccessible`, `isCreateable`, `isUpdateable`,
  `isDeletable`) before each read or write.
- A field check for each field, or a `Security.stripInaccessible` call and its
  removed-fields map.
- `WITH USER_MODE` or `AccessLevel.USER_MODE` on each query and DML statement.
- The error message, built by hand from the describe results.
- A savepoint and rollback around a save that both inserts and updates.

## What the platform does underneath

### Reading

- `query(soql, binds)` runs `Database.queryWithBinds` in user mode, so the user's
  object permissions, field permissions and sharing apply to every object and
  field in the query: the fields selected, the filters, the order, related
  objects and subqueries.
- When user mode refuses the query for access, Salesforce reports which fields
  (`QueryException.getInaccessibleFields()`). The platform raises
  `AccessDeniedException` with the first object and field in the message, and all
  of them available on the exception.
- Any other query error, such as a mistake in the SOQL, is raised as the
  `QueryException` Salesforce gives, unchanged.
- There is no read that leaves out unreadable fields in this version. Running the
  query in system mode and removing fields afterwards is weaker than user mode: a
  filter or order on a hidden field still shapes the result, and the user can learn
  its value by trying filters. A safe version needs the platform to build the
  field list itself, which is a query builder and its own module.

### Saving

- `save(records)` inserts the records that have no Id and updates the ones that
  have one. `remove(records)` deletes.
- Before any DML it checks the object: may the user create, edit or delete it.
  `remove` checks the object only, since a delete writes no fields.
- It then decides which fields each record writes (see the next section) and
  checks them with `Security.stripInaccessible` and the matching access type. A
  field the user may not edit is refused, unless the developer asked to leave it
  out with `leavingOutUneditable()`, and the fields it left out are then on
  `ForgeAccess.lastLeftOut()`: a set of `Object.Field` names for the whole save,
  not one per record.
- A short, fixed list of fields that Salesforce itself maintains is never written
  and never refused: the Id, the audit fields (`CreatedDate`, `CreatedById`,
  `LastModifiedDate`, `LastModifiedById`, `SystemModstamp`), formula and roll-up
  fields, and auto-numbers. A record read from the database carries them, and the
  user did not set them. The platform finds them by describe: the audit names,
  `isCalculated()` (formulas and roll-ups) and `isAutoNumber()`. Other fields
  Salesforce maintains, such as `Opportunity.IsClosed` and `ExpectedRevenue`, are
  not on the list, so a component that sends a whole Opportunity back is refused
  for them. The build proves each kind in an org. Every other field
  goes through the check above and is written in user mode: a field whose access
  cannot be set in a permission set but that the user may still write, such as a
  required field, is not dropped. A field that can be set on create but not on
  update is refused on update with the same "You cannot edit" error.
- It writes a new record per input record, holding the Id and only the fields it
  decided to write, a cleared field included as null. So nothing the user did not
  mean to change reaches the DML. When the save succeeds, each new Id is set on
  the developer's own record.
- It runs the DML in user mode. A save that inserts and updates sets a savepoint
  first, and rolls back both when either fails, so the save is all or nothing as
  one plain `insert` or `update` is. After a rollback no Id is set on the
  developer's records.

### Which fields a save writes

- **A record this transaction read through `query`:** only the fields that differ
  from what `query` returned. Text that changes in case only, "Acme" to "ACME",
  is a change. The platform remembers each record it returned, by
  Id, for the rest of the transaction; a later `query` or `save` of the same
  record replaces what it remembers. This is for Apex that reads, changes and
  saves records in one transaction, such as a batch job or a trigger's follow-up
  work.
- **Any other record,** new or sent from a component: every field set on it. Over
  Lightning the read and the save are two transactions, so the component sends
  only what changed, as the scenario does. A component that sends whole records
  back would have every field checked, and a read-only amount would refuse the
  save.

### The error

`ForgeAccess.AccessDeniedException` is raised only for a missing permission: the
object and field checks before the DML, or a user-mode query that Salesforce
refuses for an object or field permission. A record the user may see but not
edit because of sharing is not a permission: that save raises the `DmlException`
Salesforce gives (`INSUFFICIENT_ACCESS_OR_READONLY`), unchanged. `AccessDeniedException` holds the object, the field and the kind of
access (read, create, edit or delete) that was missing. Its message is one
sentence a user can read: "You cannot edit Opportunity.Amount.", or "You cannot
read Opportunity." when the whole object is closed to the user. It names the
object and field by their API names, which do not change with the user's language
and are what an admin looks for in a permission set. When several fields fail, the
message names the first one and says how many more there are. The build confirms
in an org that a Lightning component receives this message as it is when the
controller does not catch it; if the message does not arrive, that becomes a
question for Will before the sample is final.

A validation rule, a locked record or any other DML error is raised as the
`DmlException` Salesforce gives, after the rollback.

The build's tests cover each kind of field above: a writable field whose access a
permission set cannot change, an audit field, a formula, a roll-up and an
auto-number, a field writable on create but not on update, and an ordinary field
the user's permission sets deny.

## How it will be measured

At 1, 200 and 2,000 Opportunities, as a Standard User with a permission set:
`query`, a stage-only change in the same transaction, then `save`, against the
same work in plain user-mode Apex with the same checks written by hand. Also
`save` of records holding only an Id and a changed stage, as the table sends.
Measured: CPU, heap, queries, DML, and the consumer lines for the scenario's
controller in both versions. The describe and strip calls are where the cost will
be; heap grows with the remembered records, and a mixed save spends one more DML
statement on the savepoint.

## Decisions

Will decided these on 2026-10-15.

1. **Name.** `ForgeAccess`.
2. **How a query is written.** A SOQL string with a map of binds. A query builder,
   and a read that leaves out unreadable fields, are not in this version.
3. **What happens by default when a field fails on save.** The save is refused
   with the error; leaving the field out is the explicit choice,
   `leavingOutUneditable()`.
4. **Saving records read earlier in the same transaction.** A record read through
   `query` in the same transaction writes only the fields that changed since.
5. **One `save` or separate verbs.** One `save` that inserts or updates by Id,
   plus `remove`.
6. **Partial success.** All or nothing: a save that both inserts and updates sets
   a savepoint and rolls back both when either fails.

## Decisions taken with the design

- **User mode always.** Every query and DML statement runs in user mode. No
  system-mode switch and no system-mode read in this module; code that needs
  system mode uses plain Apex where it is visible.
- **Sharing comes from Salesforce,** through user mode. The platform adds no
  sharing logic of its own.
- **ForgeIntegration unchanged** in the first version. It already reads and saves
  in user mode; whether it moves onto this module is a later choice.
