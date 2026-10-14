/**
 * Checks the runner's comparison with canned results, with no org:
 *
 *   npm run test:perf
 */
const assert = require("node:assert/strict");
const { test } = require("node:test");
const {
  checkedSameOrgBaseline,
  compareWithBaseline,
  exitCodeFor,
  EXIT_REGRESSION,
  EXIT_UNCOMPARED,
  publishedRun,
  summarize,
} = require("./run-benchmarks");

const THRESHOLDS = {
  cpu_time: 0.25,
  counts: 0.1,
  heap: 0.1,
  heap_min_bytes: 512,
};
const ORG_ID = "00DTEST000000001";

/** One scenario whose five runs all handled `handled` of its records, at the given CPU time. */
function scenario(records, cpuTimeMs, handled = records) {
  const runs = Array.from({ length: 5 }, () => ({
    cpu_time_ms: cpuTimeMs,
    heap_bytes: 1000,
    soql_queries: 1,
    query_rows: records,
    dml_statements: 1,
    dml_rows: records,
    wall_time_ms: cpuTimeMs,
    records_handled: handled,
  }));
  const complete = handled === records;
  const { heap_bytes: heapBytes, ...others } = runs[0];
  return {
    module: "trigger-handler",
    records,
    complete,
    ...(complete && { median: others, largest: { heap_bytes: heapBytes } }),
    runs,
  };
}

/** A results file with the given scenarios. */
function results(commit, runAt, scenarios) {
  return {
    date: runAt.slice(0, 10),
    run_at: runAt,
    commit,
    org_id: ORG_ID,
    results: scenarios,
  };
}

const PUBLISHED = results("aaaaaaa", "2026-10-01T10:00:00Z", [
  scenario(1, 100),
  scenario(200, 400),
]);

/** A candidate that is twice as slow at every size, against the given same-org baseline. */
function slowCandidate(baselineScenarios) {
  const candidate = results("bbbbbbb", "2026-10-13T10:00:00Z", [
    scenario(1, 200),
    scenario(200, 800),
  ]);
  candidate.same_org_baseline = results(
    "aaaaaaa",
    "2026-10-13T09:00:00Z",
    baselineScenarios,
  );
  return candidate;
}

test("a slow candidate against an incomplete baseline is not compared and fails", () => {
  const candidate = slowCandidate([scenario(1, 100, 0), scenario(200, 400)]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.deepEqual(comparison.uncompared, ["trigger-handler 1"]);
  assert.equal(exitCodeFor(comparison, false), EXIT_UNCOMPARED);
});

test("a size missing from the baseline is not compared and fails", () => {
  const candidate = slowCandidate([scenario(1, 100)]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.deepEqual(comparison.uncompared, ["trigger-handler 200"]);
  assert.equal(exitCodeFor(comparison, false), EXIT_UNCOMPARED);
});

test("a slow candidate against a complete baseline is a regression", () => {
  const candidate = slowCandidate([scenario(1, 100), scenario(200, 400)]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.deepEqual(comparison.uncompared, []);
  assert.equal(comparison.regressions.length, 2);
  assert.equal(exitCodeFor(comparison, false), EXIT_REGRESSION);
});

test("a candidate within thresholds passes", () => {
  const candidate = slowCandidate([scenario(1, 190), scenario(200, 780)]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.equal(exitCodeFor(comparison, false), 0);
});

test("a rebuild only reports, even when a size is not compared", () => {
  const candidate = slowCandidate([]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.equal(comparison.uncompared.length, 2);
  assert.equal(exitCodeFor(comparison, true), 0);
});

test("a baseline from another org is refused", () => {
  assert.throws(
    () => checkedSameOrgBaseline(PUBLISHED, "00DTEST000000002", PUBLISHED),
    /measured in org 00DTEST000000001, not in 00DTEST000000002/,
  );
});

test("a baseline that recorded no org is refused", () => {
  const { org_id: _unused, ...withoutOrg } = PUBLISHED;
  assert.throws(
    () => checkedSameOrgBaseline(withoutOrg, ORG_ID, PUBLISHED),
    /not recorded/,
  );
});

test("a baseline from this org at the last published commit is used", () => {
  assert.equal(checkedSameOrgBaseline(PUBLISHED, ORG_ID, PUBLISHED), PUBLISHED);
});

/** A test-class benchmark's report for one size, whose two jobs had used the given CPU time by the end of the second, and whose second job saved the given rows. */
function jobReport(
  records,
  jobHeapBytes,
  cpuAfterSecondJobMs,
  secondJobDmlRows,
) {
  return {
    records,
    recordsHandled: records,
    cpuTimeMs: 20,
    heapBytes: 1000,
    soqlQueries: 1,
    queryRows: records,
    dmlStatements: 1,
    dmlRows: records,
    wallTimeMs: 40,
    callouts: 0,
    jobsQueued: 2,
    failures: 0,
    jobs: [
      {
        cpuTimeMs: 100,
        heapBytes: jobHeapBytes,
        soqlQueries: 1,
        queryRows: 1,
        dmlStatements: 1,
        dmlRows: 100,
        callouts: 1,
      },
      {
        cpuTimeMs: cpuAfterSecondJobMs,
        heapBytes: 500,
        soqlQueries: 1,
        queryRows: 1,
        dmlStatements: 1,
        dmlRows: secondJobDmlRows,
        callouts: 1,
      },
    ],
    readableFieldsQuery: {
      fields: 58,
      cpuTimeMs: 5,
      heapBytes: 9000,
      narrowCpuTimeMs: 1,
      narrowHeapBytes: 2000,
    },
  };
}

/** A forge-http scenario from five identical test runs. */
function jobScenario(
  records,
  jobHeapBytes,
  cpuAfterSecondJobMs = 250,
  secondJobDmlRows = 100,
) {
  const runs = Array.from({ length: 5 }, () =>
    publishedRun(
      jobReport(records, jobHeapBytes, cpuAfterSecondJobMs, secondJobDmlRows),
    ),
  );
  return summarize("forge-http", records, runs);
}

/** A forge-http candidate and its same-org baseline, each with one 200-record scenario. */
function jobCandidate(baselineScenario, candidateScenario) {
  const candidate = results("bbbbbbb", "2026-10-13T10:00:00Z", [
    candidateScenario,
  ]);
  candidate.same_org_baseline = results("aaaaaaa", "2026-10-13T09:00:00Z", [
    baselineScenario,
  ]);
  return candidate;
}

const PUBLISHED_JOBS = results("aaaaaaa", "2026-10-01T10:00:00Z", [
  jobScenario(200, 4000),
]);

test("a job's CPU time is its reading less the job's before it, and its trigger heap keeps the largest run", () => {
  const entry = jobScenario(200, 4000);
  assert.equal(entry.median.job_cpu_time_ms, 150);
  assert.equal(entry.largest.job_trigger_heap_bytes, 4000);
  assert.equal(entry.median.jobs_run, 2);
});

test("a module published for the first time is not compared and does not fail", () => {
  const candidate = slowCandidate([scenario(1, 100), scenario(200, 400)]);
  candidate.results.push(jobScenario(200, 4000));
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.equal(
    comparison.changes.get(candidate.results.at(-1)),
    "First published run",
  );
  assert.deepEqual(comparison.uncompared, []);
});

test("a job's CPU time over its threshold is a regression", () => {
  const candidate = jobCandidate(
    jobScenario(200, 4000),
    jobScenario(200, 4000, 400),
  );
  const comparison = compareWithBaseline(
    candidate,
    [PUBLISHED_JOBS],
    THRESHOLDS,
  );
  assert.deepEqual(comparison.regressions, [
    "forge-http 200: job_cpu_time_ms +100%",
  ]);
});

test("the heap read in a job's trigger is kept but not checked", () => {
  const candidate = jobCandidate(
    jobScenario(200, 4000),
    jobScenario(200, 8000),
  );
  const comparison = compareWithBaseline(
    candidate,
    [PUBLISHED_JOBS],
    THRESHOLDS,
  );
  assert.deepEqual(comparison.regressions, []);
});

test("a job's DML rows alone over their threshold are a regression", () => {
  const candidate = jobCandidate(
    jobScenario(200, 4000),
    jobScenario(200, 4000, 250, 150),
  );
  const comparison = compareWithBaseline(
    candidate,
    [PUBLISHED_JOBS],
    THRESHOLDS,
  );
  assert.deepEqual(comparison.regressions, [
    "forge-http 200: job_dml_rows +50%",
  ]);
});

test("each job's reading is kept in the runs but not summarized", () => {
  const entry = jobScenario(200, 4000);
  assert.equal(entry.runs[0].job_readings.length, 2);
  assert.equal(entry.median.job_readings, undefined);
  assert.equal(entry.median.job_dml_rows, 100);
});
