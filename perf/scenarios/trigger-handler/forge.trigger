trigger LeadTrigger on Lead(before insert, before update) {
  ForgeTriggerDispatcher.run(new LeadRatingHandler());
}
