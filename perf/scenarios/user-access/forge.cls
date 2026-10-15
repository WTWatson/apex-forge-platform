/**
 * A sales rep sees an account's open opportunities in a table, changes stages and
 * amounts, and saves; the controller reads and saves with the rep's permissions.
 */

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
