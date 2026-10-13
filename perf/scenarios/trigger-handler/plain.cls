/**
 * Rates a lead from its company's annual revenue: Hot from 1,000,000, Warm below.
 */
public with sharing class LeadRating {
  private static final Decimal HOT_REVENUE = 1000000;

  public static void rate(List<Lead> leads, Map<Id, Lead> previousLeads) {
    for (Lead prospect : leads) {
      Lead previous = previousLeads == null
        ? null
        : previousLeads.get(prospect.Id);
      if (
        previous == null ||
        prospect.AnnualRevenue != previous.AnnualRevenue
      ) {
        prospect.Rating = prospect.AnnualRevenue >= HOT_REVENUE
          ? 'Hot'
          : 'Warm';
      }
    }
  }
}
