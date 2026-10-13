/**
 * Benchmarks the data builder and seeder the way a consumer uses them: seeding a
 * customer account with a number of contacts.
 */
public with sharing class DataBuilderBenchmark implements ForgeBenchmark.Scenario {
  private Integer contactCount;
  private List<SObject> contacts;

  /** Notes how many contacts the seed makes; nothing else is set up. */
  public void prepare(Integer records) {
    contactCount = records;
  }

  /** Seeds the customer and its contacts. */
  public void perform() {
    contacts = CustomerSeed.customerWithContacts(contactCount);
  }

  /** Counts the seeded contacts that were saved. */
  public Integer recordsHandled() {
    Integer saved = 0;
    for (SObject contact : contacts) {
      if (contact.Id != null) {
        saved++;
      }
    }
    return saved;
  }
}
