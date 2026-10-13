/**
 * Seeds a customer account with its contacts, for tests and demos.
 */
public with sharing class CustomerSeed {
  /** Saves one customer account and the given number of named contacts under it. */
  public static List<SObject> customerWithContacts(Integer contactCount) {
    Account customer = (Account) ForgeDataBuilder.of(Account.SObjectType)
      .persist();
    return ForgeDataBuilder.of(Contact.SObjectType)
      .parent(Contact.AccountId, customer)
      .with(Contact.FirstName, ForgeDataSeeder.firstNames())
      .with(Contact.LastName, ForgeDataSeeder.lastNames())
      .with(Contact.Email, ForgeDataSeeder.emails())
      .count(contactCount)
      .persistList();
  }
}
