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

    // The tests below run through ForgeTestProductTrigger, a real trigger on Product2.

    private class ProductCountingHandler extends ForgeTriggerHandler {
        public Map<System.TriggerOperation, Integer> recordsHandled =
            new Map<System.TriggerOperation, Integer>();

        protected override void onTrigger(ForgeTriggerContext ctx) {
            Integer handledSoFar = recordsHandled.containsKey(ctx.operationType)
                ? recordsHandled.get(ctx.operationType) : 0;
            recordsHandled.put(ctx.operationType, handledSoFar + ctx.newRecords.size());
        }

        public Integer handledOn(System.TriggerOperation operation) {
            return recordsHandled.containsKey(operation) ? recordsHandled.get(operation) : 0;
        }
    }

    private class SelfRefiringHandler extends ForgeTriggerHandler {
        private final Integer maxReEntries;
        public Integer afterInsertRuns = 0;

        SelfRefiringHandler(Integer maxReEntries) {
            this.maxReEntries = maxReEntries;
        }

        public override Integer getMaxReEntries() {
            return maxReEntries;
        }

        protected override void onTrigger(ForgeTriggerContext ctx) {
            if (ctx.operationType != System.TriggerOperation.AFTER_INSERT) { return; }
            afterInsertRuns++;
            insert new Product2(Name = 'Re-fired ' + afterInsertRuns);
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

    private static List<Product2> newProducts(Integer count)
    {
        List<Product2> products = new List<Product2>();
        for (Integer i = 0; i < count; i++)
        {
            products.add(new Product2(Name = 'Product ' + i));
        }
        return products;
    }

    @IsTest
    static void everyRecordIsHandledWhenOneInsertSpansManyChunks()
    {
        ProductCountingHandler handler = new ProductCountingHandler();
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert newProducts(2000);
        Test.stopTest();

        Assert.areEqual(2000, handler.handledOn(System.TriggerOperation.BEFORE_INSERT),
            'Every chunk of a large insert should reach the handler before insert');
        Assert.areEqual(2000, handler.handledOn(System.TriggerOperation.AFTER_INSERT),
            'Every chunk of a large insert should reach the handler after insert');
        Assert.areEqual(20, ForgeTriggerHandler.getRunCount('ProductCountingHandler'),
            'Ten chunks of 200, before and after insert, should be twenty runs');
    }

    @IsTest
    static void oneHandlerRunsOnBothBeforeAndAfterInsert()
    {
        ProductCountingHandler handler = new ProductCountingHandler();
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert newProducts(5);
        Test.stopTest();

        Assert.areEqual(5, handler.handledOn(System.TriggerOperation.BEFORE_INSERT),
            'The handler should run before insert');
        Assert.areEqual(5, handler.handledOn(System.TriggerOperation.AFTER_INSERT),
            'The handler should run after insert as well');
    }

    @IsTest
    static void insertThenUpdateInOneTransactionBothRun()
    {
        ProductCountingHandler handler = new ProductCountingHandler();
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };
        List<Product2> products = newProducts(3);

        Test.startTest();
        insert products;
        for (Product2 product : products) { product.Description = 'Updated'; }
        update products;
        Test.stopTest();

        Assert.areEqual(3, handler.handledOn(System.TriggerOperation.AFTER_INSERT),
            'The handler should run for the insert');
        Assert.areEqual(3, handler.handledOn(System.TriggerOperation.AFTER_UPDATE),
            'The handler should run again for the later update');
    }

    @IsTest
    static void singleRecordIsHandledOncePerEvent()
    {
        ProductCountingHandler handler = new ProductCountingHandler();
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert new Product2(Name = 'Single');
        Test.stopTest();

        Assert.areEqual(1, handler.handledOn(System.TriggerOperation.BEFORE_INSERT));
        Assert.areEqual(1, handler.handledOn(System.TriggerOperation.AFTER_INSERT));
        Assert.areEqual(2, ForgeTriggerHandler.getRunCount('ProductCountingHandler'),
            'One record should give one run before and one after insert');
    }

    @IsTest
    static void handlerRefiringItselfIsStoppedAtTheDefaultLimit()
    {
        SelfRefiringHandler handler = new SelfRefiringHandler(1);
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert new Product2(Name = 'Original');
        Test.stopTest();

        Assert.areEqual(1, handler.afterInsertRuns,
            'With the default limit the handler should not run inside its own run');
        Assert.areEqual(2, [SELECT COUNT() FROM Product2],
            'Only the original and the first re-fired product should exist');
    }

    @IsTest
    static void raisingTheLimitAllowsOneMoreNestedLevel()
    {
        SelfRefiringHandler handler = new SelfRefiringHandler(2);
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert new Product2(Name = 'Original');
        Test.stopTest();

        Assert.areEqual(2, handler.afterInsertRuns,
            'A limit of two should allow exactly one nested run');
        Assert.areEqual(3, [SELECT COUNT() FROM Product2],
            'The original plus one re-fired product per run should exist');
    }

    @IsTest
    static void bypassWinsOverEveryRun()
    {
        ProductCountingHandler handler = new ProductCountingHandler();
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };
        ForgeTriggerHandler.bypass('ProductCountingHandler');

        Test.startTest();
        insert newProducts(201);
        Test.stopTest();

        Assert.areEqual(0, handler.handledOn(System.TriggerOperation.BEFORE_INSERT),
            'A bypassed handler should handle no records');
        Assert.areEqual(0, ForgeTriggerHandler.getRunCount('ProductCountingHandler'),
            'A bypassed handler should record no runs');
    }

    @IsTest
    static void handlerRunsAgainAfterAFailedRun()
    {
        FailOnceHandler handler = new FailOnceHandler();
        ForgeTestProductHandlers.active = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        try
        {
            insert new Product2(Name = 'Fails');
            Assert.fail('The first insert should fail in the handler');
        }
        catch (DmlException e)
        {
            Assert.isTrue(e.getMessage().contains('Failing on purpose'), e.getMessage());
        }
        insert new Product2(Name = 'Succeeds');
        Test.stopTest();

        Assert.areEqual(2, handler.completedRuns,
            'A failed run should not leave the handler counted as still running');
    }
}
