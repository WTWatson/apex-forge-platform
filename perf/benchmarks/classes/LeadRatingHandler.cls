/**
 * Rates a lead from its company's annual revenue: Hot from 1,000,000, Warm below.
 */
public with sharing class LeadRatingHandler extends ForgeTriggerHandler {
  private static final Decimal HOT_REVENUE = 1000000;

  protected override void onTrigger(ForgeTriggerContext ctx) {
    for (Lead prospect : (List<Lead>) ctx.newRecords) {
      if (ctx.hasChanged(prospect, Lead.AnnualRevenue)) {
        prospect.Rating = prospect.AnnualRevenue >= HOT_REVENUE
          ? 'Hot'
          : 'Warm';
      }
    }
  }
}
