@IsTest
private class ForgeTriggerHandlerTest {

    private class TestHandler extends ForgeTriggerHandler {
        public Integer triggerCount = 0;
        public System.TriggerOperation lastOperation;

        protected override void onTrigger(ForgeTriggerContext ctx) {
            triggerCount++;
            lastOperation = ctx.operationType;
        }
    }

    private class ReEntrantHandler extends ForgeTriggerHandler {
        public Integer triggerCount = 0;

        public override Integer getMaxReEntries() {
            return 3;
        }

        protected override void onTrigger(ForgeTriggerContext ctx) {
            triggerCount++;
        }
    }

    @IsTest
    static void bypassPreventsExecution()
    {
        ForgeTriggerHandler.bypass('TestHandler');

        Assert.isTrue(ForgeTriggerHandler.isBypassed('TestHandler'),
            'Handler should be bypassed');

        ForgeTriggerHandler.clearBypass('TestHandler');

        Assert.isFalse(ForgeTriggerHandler.isBypassed('TestHandler'),
            'Bypass should be cleared');
    }

    @IsTest
    static void clearAllBypasses()
    {
        ForgeTriggerHandler.bypass('HandlerA');
        ForgeTriggerHandler.bypass('HandlerB');

        ForgeTriggerHandler.clearAllBypasses();

        Assert.isFalse(ForgeTriggerHandler.isBypassed('HandlerA'));
        Assert.isFalse(ForgeTriggerHandler.isBypassed('HandlerB'));
    }

    @IsTest
    static void defaultMaxReEntriesIsOne()
    {
        TestHandler handler = new TestHandler();
        Assert.areEqual(1, handler.getMaxReEntries(),
            'Default max re-entries should be 1');
    }

    @IsTest
    static void overriddenMaxReEntries()
    {
        ReEntrantHandler handler = new ReEntrantHandler();
        Assert.areEqual(3, handler.getMaxReEntries(),
            'Overridden max re-entries should be 3');
    }

    @IsTest
    static void getRunCountTracksExecutions()
    {
        Assert.areEqual(0, ForgeTriggerHandler.getRunCount('TestHandler'),
            'Initial run count should be 0');
    }

    @IsTest
    static void resetRunCountsClearsState()
    {
        ForgeTriggerHandler.resetRunCounts();
        Assert.areEqual(0, ForgeTriggerHandler.getRunCount('TestHandler'));
    }

    @IsTest
    static void onTriggerReceivesContext()
    {
        TestHandler handler = new TestHandler();
        ForgeTriggerContext ctx = ForgeTriggerContext.forInsert(
            new List<Account>{ new Account(Name = 'Test') }
        );

        handler.onTrigger(ctx);

        Assert.areEqual(1, handler.triggerCount);
        Assert.areEqual(System.TriggerOperation.BEFORE_INSERT, handler.lastOperation);
    }

    @IsTest
    static void contextOperationTypeIsSet()
    {
        ForgeTriggerContext ctx = ForgeTriggerContext.forInsert(
            new List<Account>{ new Account(Name = 'Test') }
        );

        Assert.areEqual(System.TriggerOperation.BEFORE_INSERT, ctx.operationType);
    }

    @IsTest
    static void hasChangedReturnsTrueOnInsert()
    {
        ForgeTriggerContext ctx = ForgeTriggerContext.forInsert(
            new List<Account>{ new Account(Name = 'Test') }
        );

        Assert.isTrue(ctx.hasChanged(ctx.newRecords[0], Account.Name),
            'hasChanged should return true when oldMap is null (insert)');
    }

    @IsTest
    static void hasChangedDetectsFieldChange()
    {
        Account oldAcc = new Account(Id = '001000000000001AAA', Name = 'Old Name');
        Account newAcc = new Account(Id = '001000000000001AAA', Name = 'New Name');

        ForgeTriggerContext ctx = ForgeTriggerContext.forUpdate(
            new List<Account>{ newAcc },
            new List<Account>{ oldAcc }
        );

        Assert.isTrue(ctx.hasChanged(newAcc, Account.Name),
            'hasChanged should return true when field value differs');
    }

    @IsTest
    static void hasChangedReturnsFalseWhenUnchanged()
    {
        Account oldAcc = new Account(Id = '001000000000001AAA', Name = 'Same');
        Account newAcc = new Account(Id = '001000000000001AAA', Name = 'Same');

        ForgeTriggerContext ctx = ForgeTriggerContext.forUpdate(
            new List<Account>{ newAcc },
            new List<Account>{ oldAcc }
        );

        Assert.isFalse(ctx.hasChanged(newAcc, Account.Name),
            'hasChanged should return false when field value is the same');
    }

    @IsTest
    static void dispatcherRunsListInOrder()
    {
        TestHandler h1 = new TestHandler();
        TestHandler h2 = new TestHandler();

        ForgeTriggerHandler.bypass('TestHandler');
        ForgeTriggerDispatcher.run(new List<ForgeTriggerHandler>{ h1, h2 });
        ForgeTriggerHandler.clearAllBypasses();
    }
}
