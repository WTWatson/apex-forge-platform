# ForgeAccess: the running user's permissions, checked for you

A developer whose code reads or saves records for a user should write which
records and which fields, and nothing about checking that user's object and field
permissions. The platform checks them before it reads or writes. It runs the query
and the DML in user mode, and when a check fails it raises one error naming the
object and the field.

The name `ForgeAccess` is a proposal; see "Questions for Will".

## The scenario

A sales rep opens an account in Lightning and sees its open opportunities in a
small component: name, stage, amount and close date. The rep changes stages and
amounts in the component and saves. Some reps may read the amount but not edit it.
The component calls an Apex controller, and that controller must respect the rep's
permissions: read only what the rep may read, and save only what the rep may edit.

### What the developer writes

```apex
/** The open opportunities a sales rep works on an account, read and saved with the rep's permissions. */
public with sharing class OpenOpportunities
{
    /** The account's open opportunities, with the fields the board shows. */
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> forAccount(Id accountId)
    {
        return ForgeAccess.query(
            'SELECT Name, StageName, Amount, CloseDate FROM Opportunity'
                + ' WHERE AccountId = :accountId AND IsClosed = false',
            new Map<String, Object>{ 'accountId' => accountId }
        );
    }

    /** Saves the stages and amounts the rep changed. */
    @AuraEnabled
    public static void save(List<Opportunity> opportunities)
    {
        ForgeAccess.save(opportunities);
    }
}
```

If the rep may not read `Amount`, `forAccount` raises
`ForgeAccess.AccessDeniedException` with the message
"You cannot read Opportunity.Amount." If the rep may read it but not edit it and
changed it, `save` raises "You cannot edit Opportunity.Amount." and saves nothing.
In both cases the component shows that message as it is.

A developer who would rather leave out what the user may not see asks for it in
the same line:

```apex
return ForgeAccess.leavingOutUnreadable().query(soql, binds);
```

The records then come back without `Amount`, and nothing is raised.

A test of the controller runs it as a user with the permission set it needs, as
any user-mode test does. The platform adds no test setup of its own.

### What the developer does not write

- An object check (`isAccessible`, `isCreateable`, `isUpdateable`,
  `isDeletable`) before each read or write.
- A field check for each field, or a `Security.stripInaccessible` call and its
  removed-fields map.
- `WITH USER_MODE` or `AccessLevel.USER_MODE` on each query and DML statement.
- The error message, built by hand from the describe results.
- A cast from `List<SObject>`: `query` returns a list of the queried object, as
  `Database.query` does.

## What the platform does underneath

### Reading

- `query(soql, binds)` runs `Database.queryWithBinds` in user mode, so the
  user's object permissions, field permissions and sharing all apply.
- When user mode refuses a field, Salesforce reports which ones
  (`QueryException.getInaccessibleFields()`). The platform raises
  `AccessDeniedException` with the first object and field in the message, and all
  of them available on the exception.
- `leavingOutUnreadable().query(...)` first checks the object, and raises if the
  user may not read it at all. It then runs the query in system mode, keeping the
  sharing of the calling class, and removes the fields the user may not read with
  `Security.stripInaccessible`. The fields it left out are available afterwards,
  so a component can say what it did not show.

### Saving

- `save(records)` inserts the records that have no Id and updates the ones that
  have one. `remove(records)` deletes.
- Before any DML it checks the object: may the user create, edit or delete it.
- It then checks each field set on the records, with
  `Security.stripInaccessible` and the matching access type. A field no user can
  ever edit, such as `CreatedDate` or a formula, is ignored, because a record read
  from the database carries such fields and the DML never writes them. A field the
  user lacks permission to edit is refused, unless the developer asked to leave it
  out with `leavingOutUneditable().save(...)`.
- Last, it runs the DML in user mode, all or nothing, as a plain `insert` or
  `update` does.

### Which fields count as changed

A record read and then saved carries every field the query returned. Checking all
of them would refuse a save where the rep changed only the stage, because the
record still holds an amount the rep may read but not edit. So the platform
remembers what `query` returned in this transaction and checks only the fields
that differ on save. A record it did not read, such as a new one or one sent back
from a component, has every field set on it checked. Question 4 asks Will to
choose this.

### The error

`ForgeAccess.AccessDeniedException` holds the object, the field and the kind of
access (read, create, edit or delete) that was missing. Its message is one
sentence a user can read: "You cannot edit Opportunity.Amount." When several
fields fail, the message names the first one and says how many more there are.

## How it will be measured

At 1, 200 and 2,000 Opportunities, as a Standard User with a permission set:
`query` and then `save` through the platform, against the same work in plain
user-mode Apex. The plain version does the same checks by hand. Measured: CPU,
heap, queries, DML, and the consumer lines for the scenario's controller in both
versions. The describe and strip calls are where the cost will be; heap grows with
the remembered values from the previous section.

## Questions for Will

1. **Name.** `ForgeAccess` (recommended), `ForgeSecurity` or `ForgeUserMode`.
2. **How a query is written.** A SOQL string with a map of binds, as above
   (recommended). The other choice is a small query builder, which is larger and
   is its own module. Static SOQL in brackets cannot be passed to the platform
   before it runs.
3. **What happens by default when a field fails.** Refuse with the error
   (recommended), with leaving it out as the explicit choice. The opposite default
   quietly hands business logic records with missing fields.
4. **Saving records read earlier.** Check only the fields that changed since
   `query` read them (recommended), or check every field set on the record.
5. **One `save` or separate verbs.** One `save` that inserts or updates by Id, plus
   `remove` (recommended), or `insert`, `update` and `remove` as in plain Apex.
6. **Partial success.** All or nothing, as plain DML (recommended), or save what
   passes and report the rest, as `Database.update(records, false)` does.
7. **Filters when leaving fields out.** In `leavingOutUnreadable()`, the
   platform cannot see which fields the `WHERE` and `ORDER BY` use, so a query can
   filter on a field the user may not read. Accept it and say so in the method's
   purpose line (recommended), or offer leaving out on saves only.

## Decisions already taken

- **User mode always.** No system-mode switch in this module; code that needs
  system mode uses plain Apex where it is visible.
- **Sharing comes from Salesforce,** through user mode or the calling class's
  sharing. The platform adds no sharing logic of its own.
- **ForgeIntegration unchanged** in the first version. It already reads and saves
  in user mode; whether it moves onto this module is a later choice.
