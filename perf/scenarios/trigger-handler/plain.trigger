trigger LeadTrigger on Lead(before insert, before update) {
  LeadRating.rate(Trigger.new, (Map<Id, Lead>) Trigger.oldMap);
}
