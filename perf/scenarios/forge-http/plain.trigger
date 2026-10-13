trigger AccountTrigger on Account (after insert)
{
    SendCustomersToErp.start(Trigger.new);
}
