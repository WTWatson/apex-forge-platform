/**
 * The same controller as forge.cls in plain Apex: the query and the save run in user
 * mode, and the object and field checks and their messages are written by hand.
 */

/** The open opportunities a sales rep works on an account, read and saved with the rep's permissions. */
public with sharing class OpenOpportunities
{
    /** Raised when the rep may not read or edit the opportunities or one of their fields. */
    public class AccessDeniedException extends Exception {}

    /** The account's open opportunities, with the fields the table shows. */
    @AuraEnabled(cacheable=true)
    public static List<Opportunity> forAccount(Id accountId)
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

    /** Saves the stages and amounts the rep changed in the table. */
    @AuraEnabled
    public static void save(List<Opportunity> changes)
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

    // Names the first field refused, in name order, and counts the rest, as in "You cannot edit Opportunity.Amount and 2 more fields."
    private static AccessDeniedException denied(String verb, Map<String, Set<String>> fieldsByObject)
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
