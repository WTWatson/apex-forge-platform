@IsTest
private class ForgeTriggerHandlerOnProductTest {

    // These tests run through ForgeTestProductTrigger, a real trigger on Product2,
    // so they cover what only a trigger does: 200-record chunks and before/after events.

    private class ProductCountingHandler extends ForgeTriggerHandler {
        public Map<System.TriggerOperation, Integer> recordsHandled =
            new Map<System.TriggerOperation, Integer>();

        protected override void onTrigger(ForgeTriggerContext ctx) {
            recordsHandled.put(ctx.operationType, handledOn(ctx.operationType) + ctx.newRecords.size());
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
        ForgeTestProductHandlers.toRun = new List<ForgeTriggerHandler>{ handler };

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
        ForgeTestProductHandlers.toRun = new List<ForgeTriggerHandler>{ handler };

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
        ForgeTestProductHandlers.toRun = new List<ForgeTriggerHandler>{ handler };
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
        ForgeTestProductHandlers.toRun = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert new Product2(Name = 'Single');
        Test.stopTest();

        Assert.areEqual(1, handler.handledOn(System.TriggerOperation.BEFORE_INSERT));
        Assert.areEqual(1, handler.handledOn(System.TriggerOperation.AFTER_INSERT));
        Assert.areEqual(2, ForgeTriggerHandler.getRunCount('ProductCountingHandler'),
            'One record should give one run before and one after insert');
    }

    @IsTest
    static void handlerRefiringItsOwnTriggerIsStoppedAtTheDefaultLimit()
    {
        SelfRefiringHandler handler = new SelfRefiringHandler(1);
        ForgeTestProductHandlers.toRun = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert new Product2(Name = 'Original');
        Test.stopTest();

        Assert.areEqual(1, handler.afterInsertRuns,
            'With the default limit the handler should not run inside its own run');
        Assert.areEqual(2, [SELECT COUNT() FROM Product2],
            'Only the original and the first re-fired product should exist');
    }

    @IsTest
    static void raisingTheLimitAllowsOneMoreNestedTriggerLevel()
    {
        SelfRefiringHandler handler = new SelfRefiringHandler(2);
        ForgeTestProductHandlers.toRun = new List<ForgeTriggerHandler>{ handler };

        Test.startTest();
        insert new Product2(Name = 'Original');
        Test.stopTest();

        Assert.areEqual(2, handler.afterInsertRuns,
            'A limit of two should allow exactly one nested run');
        Assert.areEqual(3, [SELECT COUNT() FROM Product2],
            'The original plus one re-fired product per run should exist');
    }

    @IsTest
    static void bypassWinsOverEveryChunk()
    {
        ProductCountingHandler handler = new ProductCountingHandler();
        ForgeTestProductHandlers.toRun = new List<ForgeTriggerHandler>{ handler };
        ForgeTriggerHandler.bypass('ProductCountingHandler');

        Test.startTest();
        insert newProducts(201);
        Test.stopTest();

        Assert.areEqual(0, handler.handledOn(System.TriggerOperation.BEFORE_INSERT),
            'A bypassed handler should handle no records');
        Assert.areEqual(0, ForgeTriggerHandler.getRunCount('ProductCountingHandler'),
            'A bypassed handler should record no runs');
    }
}
