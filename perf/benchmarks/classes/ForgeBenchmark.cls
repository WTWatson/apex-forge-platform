/**
 * Measures one consumer scenario of a platform module at a given record count, so
 * the cost of using the module can be published with it.
 */
public with sharing class ForgeBenchmark {
  /** The start of the log line the runner reads a measurement from. */
  public static final String REPORT_PREFIX = 'FORGE_BENCHMARK ';

  private static final Map<String, Type> SCENARIOS = new Map<String, Type>{
    'trigger-handler' => TriggerHandlerBenchmark.class,
    'data-builder' => DataBuilderBenchmark.class
  };

  /** Raised when a module has no benchmark scenario. */
  public class UnknownModuleException extends Exception {
  }

  /** One consumer scenario of a module: its setup, the call a consumer makes, and the check that it worked. */
  public interface Scenario {
    /** Sets up what the scenario needs before the measured call, such as the records to insert. */
    void prepare(Integer records);

    /** Makes the call a consumer would make; only this is measured. */
    void perform();

    /** Counts the records the scenario handled correctly, read after the measurement. */
    Integer recordsHandled();
  }

  /** The cost of one measured call, read from the governor limits and the clock around it. */
  public class Measures {
    public String module;
    public Integer records;
    public Integer cpuTimeMs;
    public Integer heapBytes;
    public Integer soqlQueries;
    public Integer queryRows;
    public Integer dmlStatements;
    public Integer dmlRows;
    public Long wallTimeMs;
    public Integer recordsHandled;
  }

  /** Measures the named module's scenario at the given record count and rolls back every record it made. */
  public static Measures measure(String module, Integer records) {
    Scenario scenario = scenarioFor(module);
    Savepoint beforeScenario = Database.setSavepoint();
    try {
      scenario.prepare(records);
      Measures measures = measurePerform(scenario);
      measures.module = module;
      measures.records = records;
      measures.recordsHandled = scenario.recordsHandled();
      return measures;
    } finally {
      Database.rollback(beforeScenario);
    }
  }

  /** Measures the named module's scenario and writes the result as one log line for the runner. */
  public static void report(String module, Integer records) {
    System.debug(
      LoggingLevel.ERROR,
      REPORT_PREFIX + JSON.serialize(measure(module, records))
    );
  }

  private static Scenario scenarioFor(String module) {
    Type scenarioType = SCENARIOS.get(module);
    if (scenarioType == null) {
      throw new UnknownModuleException(
        'No benchmark scenario for module ' + module
      );
    }
    return (Scenario) scenarioType.newInstance();
  }

  private static Measures measurePerform(Scenario scenario) {
    Integer cpuBefore = Limits.getCpuTime();
    Integer heapBefore = Limits.getHeapSize();
    Integer queriesBefore = Limits.getQueries();
    Integer queryRowsBefore = Limits.getQueryRows();
    Integer dmlBefore = Limits.getDmlStatements();
    Integer dmlRowsBefore = Limits.getDmlRows();
    Long startedAt = System.now().getTime();

    scenario.perform();

    Measures measures = new Measures();
    measures.wallTimeMs = System.now().getTime() - startedAt;
    measures.cpuTimeMs = Limits.getCpuTime() - cpuBefore;
    measures.heapBytes = Limits.getHeapSize() - heapBefore;
    measures.soqlQueries = Limits.getQueries() - queriesBefore;
    measures.queryRows = Limits.getQueryRows() - queryRowsBefore;
    measures.dmlStatements = Limits.getDmlStatements() - dmlBefore;
    measures.dmlRows = Limits.getDmlRows() - dmlRowsBefore;
    return measures;
  }
}
