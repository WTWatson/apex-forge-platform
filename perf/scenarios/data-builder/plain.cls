/**
 * Seeds a customer account with its contacts, for tests and demos.
 */
public with sharing class CustomerSeed {
  private static final List<String> FIRST_NAMES = new List<String>{
    'Agatha',
    'Alfie',
    'Archie',
    'Arthur'
  };
  private static final List<String> LAST_NAMES = new List<String>{
    'Abbott',
    'Ashby',
    'Ashworth',
    'Barnaby'
  };

  /** Saves one customer account and the given number of named contacts under it. */
  public static List<Contact> customerWithContacts(Integer contactCount) {
    Account customer = new Account(Name = 'Test');
    insert customer;
    List<Contact> contacts = new List<Contact>();
    for (Integer i = 0; i < contactCount; i++) {
      contacts.add(
        new Contact(
          AccountId = customer.Id,
          FirstName = FIRST_NAMES[Math.mod(i, FIRST_NAMES.size())],
          LastName = LAST_NAMES[Math.mod(i, LAST_NAMES.size())],
          Email = 'user' + (i + 1) + '@example.co.uk'
        )
      );
    }
    insert contacts;
    return contacts;
  }
}
