/**
 * Benchmarks the trigger handler framework the way a consumer uses it: inserting
 * leads through the lead trigger, whose handler rates each lead.
 */
public with sharing class TriggerHandlerBenchmark implements ForgeBenchmark.Scenario {
  private static final Decimal LARGE_COMPANY_REVENUE = 2000000;
  private static final Decimal SMALL_COMPANY_REVENUE = 500000;

  private List<Lead> leads;

  /** Builds the leads to insert, half from large companies and half from small ones. */
  public void prepare(Integer records) {
    leads = new List<Lead>();
    for (Integer i = 0; i < records; i++) {
      leads.add(
        new Lead(
          LastName = 'Benchmark ' + i,
          Company = 'Benchmark Company ' + i,
          AnnualRevenue = Math.mod(i, 2) == 0
            ? LARGE_COMPANY_REVENUE
            : SMALL_COMPANY_REVENUE
        )
      );
    }
  }

  /** Inserts the leads, which runs the lead trigger and its handler. */
  public void perform() {
    insert leads;
  }

  /** Counts the inserted leads that the handler gave a rating. */
  public Integer recordsHandled() {
    return [SELECT COUNT() FROM Lead WHERE Id IN :leads AND Rating != NULL];
  }
}
