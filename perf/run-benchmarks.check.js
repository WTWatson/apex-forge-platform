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
  assert.equal(exitCodeFor(comparison, { isRebuild: false }), EXIT_UNCOMPARED);
});

test("a size missing from the baseline is not compared and fails", () => {
  const candidate = slowCandidate([scenario(1, 100)]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.deepEqual(comparison.uncompared, ["trigger-handler 200"]);
  assert.equal(exitCodeFor(comparison, { isRebuild: false }), EXIT_UNCOMPARED);
});

test("a slow candidate against a complete baseline is a regression", () => {
  const candidate = slowCandidate([scenario(1, 100), scenario(200, 400)]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.deepEqual(comparison.uncompared, []);
  assert.equal(comparison.regressions.length, 2);
  assert.equal(exitCodeFor(comparison, { isRebuild: false }), EXIT_REGRESSION);
});

test("a candidate within thresholds passes", () => {
  const candidate = slowCandidate([scenario(1, 190), scenario(200, 780)]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.equal(exitCodeFor(comparison, { isRebuild: false }), 0);
});

test("a rebuild only reports, even when a size is not compared", () => {
  const candidate = slowCandidate([]);
  const comparison = compareWithBaseline(candidate, [PUBLISHED], THRESHOLDS);
  assert.equal(comparison.uncompared.length, 2);
  assert.equal(exitCodeFor(comparison, { isRebuild: true }), 0);
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
