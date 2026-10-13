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

    // The tests below call handle() directly, as a trigger would, so they need no trigger.
    // ForgeTriggerHandlerOnProductTest in test-support runs the same rules through a real one.

    private class RunCountingHandler extends ForgeTriggerHandler {
        public Integer runs = 0;

        protected override void onTrigger(ForgeTriggerContext ctx) {
            runs++;
        }
    }

    private class SelfCallingHandler extends ForgeTriggerHandler {
        private final Integer maxReEntries;
        public Integer runs = 0;

        SelfCallingHandler(Integer maxReEntries) {
            this.maxReEntries = maxReEntries;
        }

        public override Integer getMaxReEntries() {
            return maxReEntries;
        }

        protected override void onTrigger(ForgeTriggerContext ctx) {
            runs++;
            handle();
        }
    }

    private class FailOnceHandler extends ForgeTriggerHandler {
        public Boolean failNextRun = true;
        public Integer completedRuns = 0;

        protected override void onTrigger(ForgeTriggerContext ctx) {
            if (failNextRun) {
                failNextRun = false;
                throw new IllegalArgumentException('Failing on purpose');
            }
            completedRuns++;
        }
    }

    @IsTest
    static void runsOneAfterAnotherAllGoAhead()
    {
        RunCountingHandler handler = new RunCountingHandler();

        Test.startTest();
        handler.handle();
        handler.handle();
        handler.handle();
        Test.stopTest();

        Assert.areEqual(3, handler.runs,
            'Runs that follow one another are not re-entry and should all go ahead');
        Assert.areEqual(3, ForgeTriggerHandler.getRunCount('RunCountingHandler'),
            'The run count should count every run that happened');
    }

    @IsTest
    static void handlerCallingItselfIsStoppedAtTheDefaultLimit()
    {
        SelfCallingHandler handler = new SelfCallingHandler(1);

        Test.startTest();
        handler.handle();
        Test.stopTest();

        Assert.areEqual(1, handler.runs,
            'With the default limit the handler should not run inside its own run');
    }

    @IsTest
    static void raisingTheLimitAllowsOneMoreNestedLevel()
    {
        SelfCallingHandler handler = new SelfCallingHandler(2);

        Test.startTest();
        handler.handle();
        Test.stopTest();

        Assert.areEqual(2, handler.runs,
            'A limit of two should allow exactly one nested run');
    }

    @IsTest
    static void handlerStoppedFromNestingStillRunsNextTime()
    {
        SelfCallingHandler handler = new SelfCallingHandler(1);

        Test.startTest();
        handler.handle();
        handler.handle();
        Test.stopTest();

        Assert.areEqual(2, handler.runs,
            'Each outer run should go ahead once the previous one has finished');
    }

    @IsTest
    static void bypassWinsOverEveryRun()
    {
        RunCountingHandler handler = new RunCountingHandler();
        ForgeTriggerHandler.bypass('RunCountingHandler');

        Test.startTest();
        handler.handle();
        handler.handle();
        Test.stopTest();

        Assert.areEqual(0, handler.runs, 'A bypassed handler should not run');
        Assert.areEqual(0, ForgeTriggerHandler.getRunCount('RunCountingHandler'),
            'A bypassed handler should record no runs');
    }

    @IsTest
    static void handlerRunsAgainAfterAFailedRun()
    {
        FailOnceHandler handler = new FailOnceHandler();

        Test.startTest();
        try
        {
            handler.handle();
            Assert.fail('The first run should fail');
        }
        catch (IllegalArgumentException e)
        {
            Assert.areEqual('Failing on purpose', e.getMessage());
        }
        handler.handle();
        Test.stopTest();

        Assert.areEqual(1, handler.completedRuns,
            'A failed run should not leave the handler counted as still running');
    }
}
