trigger AccountTrigger on Account (after insert)
{
    ForgeTriggerDispatcher.run(new NewAccountsBecomeErpCustomers());
}
