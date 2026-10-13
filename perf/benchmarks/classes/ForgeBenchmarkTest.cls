@IsTest
private class ForgeBenchmarkTest {
  @IsTest
  static void triggerHandlerRatesEveryLeadInABulkInsert() {
    Test.startTest();
    ForgeBenchmark.Measures measures = ForgeBenchmark.measure(
      'trigger-handler',
      200
    );
    Test.stopTest();

    Assert.areEqual('trigger-handler', measures.module);
    Assert.areEqual(200, measures.records);
    Assert.areEqual(200, measures.recordsHandled, 'every lead is rated');
    Assert.areEqual(1, measures.dmlStatements, 'one insert');
    Assert.areEqual(200, measures.dmlRows);
    Assert.areEqual(0, measures.soqlQueries, 'the handler queries nothing');
    Assert.isTrue(measures.cpuTimeMs >= 0);
    Assert.isTrue(measures.wallTimeMs >= 0);
  }

  @IsTest
  static void triggerHandlerRatesASingleLead() {
    Test.startTest();
    ForgeBenchmark.Measures measures = ForgeBenchmark.measure(
      'trigger-handler',
      1
    );
    Test.stopTest();

    Assert.areEqual(1, measures.recordsHandled);
    Assert.areEqual(1, measures.dmlRows);
  }

  @IsTest
  static void dataBuilderSeedsTheCustomerAndItsContacts() {
    Test.startTest();
    ForgeBenchmark.Measures measures = ForgeBenchmark.measure(
      'data-builder',
      200
    );
    Test.stopTest();

    Assert.areEqual(200, measures.recordsHandled, 'every contact is saved');
    Assert.areEqual(
      2,
      measures.dmlStatements,
      'the account, then the contacts'
    );
    Assert.areEqual(201, measures.dmlRows);
  }

  @IsTest
  static void measuringLeavesNoRecordsBehind() {
    Test.startTest();
    ForgeBenchmark.measure('trigger-handler', 5);
    ForgeBenchmark.measure('data-builder', 5);
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM Lead]);
    Assert.areEqual(0, [SELECT COUNT() FROM Account]);
    Assert.areEqual(0, [SELECT COUNT() FROM Contact]);
  }

  @IsTest
  static void reportRollsBackLikeMeasure() {
    Test.startTest();
    ForgeBenchmark.report('trigger-handler', 1);
    Test.stopTest();

    Assert.areEqual(0, [SELECT COUNT() FROM Lead]);
  }

  @IsTest
  static void unknownModuleIsRefused() {
    try {
      ForgeBenchmark.measure('no-such-module', 1);
      Assert.fail('Expected UnknownModuleException');
    } catch (ForgeBenchmark.UnknownModuleException e) {
      Assert.isTrue(e.getMessage().contains('no-such-module'));
    }
  }
}
