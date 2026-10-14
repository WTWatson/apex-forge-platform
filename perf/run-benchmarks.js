/**
 * Runs every module's benchmark in a scratch org, keeps the median of five runs (the
 * largest for heap) and writes the results file and the README tables' rows.
 *
 *   node perf/run-benchmarks.js --org <scratch-org-alias> --baseline [--runs 5]
 *   node perf/run-benchmarks.js --org <scratch-org-alias> [--runs 5]
 *   node perf/run-benchmarks.js --rebuild docs/performance/results/<file>.json
 *
 * A change is compared with the last published commit measured in the same org,
 * because CPU time moves between orgs by more than a real slowdown would. So a
 * measurement is two passes in one org: first deploy force-app at the last published
 * commit and run with --baseline, then deploy the change and run without it. Both
 * passes record the org's Id, and the second refuses a baseline from another org.
 * The --baseline pass measures only the modules the last published run has; a module
 * published for the first time has nothing to compare with.
 * perf/benchmarks and test-support must be deployed too. Each run is one anonymous Apex
 * transaction, so every measurement starts with fresh limits. A module that runs only
 * in a test (TEST_CLASS_MODULES) is one test run per run instead, with its numbers read
 * from the debug log the runner turns on for the org's user.
 * --rebuild needs no org: it works the kept values out again from the runs already in
 * a results file, and rewrites it. It only reports, and never fails on a comparison.
 *
 * Exit codes: 2 when a measure is worse than its threshold; 3 when a size published
 * before could not be compared, because the same-org re-run did not handle every
 * record. On 3 nothing is written to docs/performance/results.
 */
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const RESULTS_DIR = path.join(ROOT, "docs", "performance", "results");
const THRESHOLDS_FILE = path.join(ROOT, "perf", "thresholds.json");
const SCENARIOS_DIR = path.join(ROOT, "perf", "scenarios");
const SAME_ORG_DIR = path.join(ROOT, "perf", ".same-org");
const REPORT_PREFIX = "FORGE_BENCHMARK ";

const DEFAULT_THRESHOLDS = {
  cpu_time: 0.25,
  counts: 0.1,
  heap: 0.1,
  heap_min_bytes: 512,
};

const MODULES = ["trigger-handler", "data-builder", "forge-http"];
const RECORD_COUNTS = [1, 200, 2000];
// Modules whose scenario runs only in a test (it needs a mock or a test-only trigger):
// one test run measures every size, and the numbers come back through the debug log.
const TEST_CLASS_MODULES = { "forge-http": "ForgeHttpBenchmark" };
const DEBUG_LEVEL = "ForgeBenchmark";

// Apex field name -> published measure name.
const MEASURES = {
  cpuTimeMs: "cpu_time_ms",
  heapBytes: "heap_bytes",
  soqlQueries: "soql_queries",
  queryRows: "query_rows",
  dmlStatements: "dml_statements",
  dmlRows: "dml_rows",
  wallTimeMs: "wall_time_ms",
  recordsHandled: "records_handled",
};
// heap_bytes is the heap the measured call added: Limits.getHeapSize() just after it
// minus just before it. Records built before the call and memory freed during it are
// not in it. The counter sometimes leaves out memory a run still holds and has not been
// seen to over-count, so the largest run is kept, under "largest"; every other measure
// is the median, under "median". All five runs can still read low. The same holds for
// every heap measure of the queued jobs.
const isLargestRunMeasure = (measure) => measure.endsWith("heap_bytes");
// The job_ measures, and callouts and jobs_queued, exist only for modules that queue
// jobs; a measure missing on either side of a comparison is skipped.
const CPU_MEASURES = ["cpu_time_ms", "job_cpu_time_ms"];
const COUNT_MEASURES = [
  "soql_queries",
  "query_rows",
  "dml_statements",
  "dml_rows",
  "callouts",
  "jobs_queued",
  "job_callouts",
  "job_soql_queries",
  "job_query_rows",
  "job_dml_statements",
];
// A job's heap is not gated: the only reading is taken in a trigger the job's save
// fires, and a trigger's heap leaves out what the job holds around the save.
const HEAP_MEASURES = ["heap_bytes"];
const NOT_PUBLISHED = "Not published yet";
const EXIT_REGRESSION = 2;
const EXIT_UNCOMPARED = 3;

function readArguments() {
  const args = process.argv.slice(2);
  const valueOf = (flag) => {
    const at = args.indexOf(flag);
    return at === -1 ? undefined : args[at + 1];
  };
  const org = valueOf("--org");
  const rebuild = valueOf("--rebuild");
  const baseline = args.includes("--baseline");
  if (!org === !rebuild || (baseline && !org)) {
    throw new Error(
      "Usage: node perf/run-benchmarks.js --org <alias> [--baseline] | --rebuild <results file>",
    );
  }
  return { org, rebuild, baseline, runs: Number(valueOf("--runs") ?? 5) };
}

function measureOnce(org, module, records) {
  const script = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "forge-bench-")),
    "run.apex",
  );
  fs.writeFileSync(script, `ForgeBenchmark.report('${module}', ${records});\n`);
  const output = execFileSync(
    "sf",
    ["apex", "run", "-o", org, "--file", script, "--json"],
    { encoding: "utf8", maxBuffer: 64 * 1024 * 1024 },
  );
  const result = JSON.parse(output).result;
  if (!result.success) {
    throw new Error(
      `${module} at ${records}: ${result.exceptionMessage || result.compileProblem}`,
    );
  }
  const line = result.logs
    .split("\n")
    .find((logLine) => logLine.includes(REPORT_PREFIX));
  return publishedRun(reportIn(line));
}

function reportIn(line) {
  return JSON.parse(
    line.slice(line.indexOf(REPORT_PREFIX) + REPORT_PREFIX.length),
  );
}

/** Renames a benchmark's report to the published measures, adding the queued jobs' where there are any. */
function publishedRun(raw) {
  const run = {};
  for (const [apexName, publishedName] of Object.entries(MEASURES)) {
    run[publishedName] = raw[apexName];
  }
  return raw.jobs ? { ...run, ...jobMeasures(raw) } : run;
}

/**
 * The queued jobs' cost, and the cost of a job's every-readable-field query against
 * reading only the fields the job uses. In a test, Test.stopTest runs every job in one
 * context where CPU time keeps adding up, so each job's CPU time is its reading less
 * the reading of the job before it. Per-job measures keep the largest job, the one
 * closest to a limit.
 */
function jobMeasures(raw) {
  const jobs = raw.jobs;
  const jobCpu = jobs.map(
    (job, at) => job.cpuTimeMs - (at ? jobs[at - 1].cpuTimeMs : 0),
  );
  const largest = (field) => Math.max(...jobs.map((job) => job[field]));
  const query = raw.readableFieldsQuery;
  return {
    callouts: raw.callouts,
    jobs_queued: raw.jobsQueued,
    jobs_run: jobs.length,
    failures: raw.failures,
    job_callouts: largest("callouts"),
    job_cpu_time_ms: Math.max(...jobCpu),
    job_trigger_heap_bytes: largest("heapBytes"),
    job_soql_queries: largest("soqlQueries"),
    job_query_rows: largest("queryRows"),
    job_dml_statements: largest("dmlStatements"),
    readable_fields: query.fields,
    field_query_cpu_time_ms: query.cpuTimeMs,
    field_query_heap_bytes: query.heapBytes,
    used_fields_query_cpu_time_ms: query.narrowCpuTimeMs,
    used_fields_query_heap_bytes: query.narrowHeapBytes,
  };
}

function sfJson(args) {
  return JSON.parse(
    execFileSync("sf", [...args, "--json"], {
      encoding: "utf8",
      maxBuffer: 64 * 1024 * 1024,
    }),
  ).result;
}

function toolingQuery(org, soql) {
  return sfJson(["data", "query", "-o", org, "--use-tooling-api", "-q", soql])
    .records;
}

function createToolingRecord(org, sobject, values) {
  return sfJson([
    "data",
    "create",
    "record",
    "-o",
    org,
    "--use-tooling-api",
    "--sobject",
    sobject,
    "--values",
    values,
  ]).id;
}

/** Makes sure the org's user is traced at a level that keeps the benchmark lines, so a test run leaves a log to read. */
function traceTheRunningUser(org) {
  const username = sfJson(["org", "display", "-o", org]).username;
  const userId = sfJson([
    "data",
    "query",
    "-o",
    org,
    "-q",
    `SELECT Id FROM User WHERE Username = '${username}'`,
  ]).records[0].Id;
  const now = new Date();
  const anHourFromNow = new Date(now.getTime() + 3600 * 1000).toISOString();
  const traced = toolingQuery(
    org,
    `SELECT Id FROM TraceFlag WHERE TracedEntityId = '${userId}' AND DebugLevel.DeveloperName = '${DEBUG_LEVEL}' AND ExpirationDate > ${anHourFromNow}`,
  );
  if (traced.length) {
    return;
  }
  const levels = toolingQuery(
    org,
    `SELECT Id FROM DebugLevel WHERE DeveloperName = '${DEBUG_LEVEL}'`,
  );
  const levelId = levels.length
    ? levels[0].Id
    : createToolingRecord(
        org,
        "DebugLevel",
        `DeveloperName=${DEBUG_LEVEL} MasterLabel=${DEBUG_LEVEL} ApexCode=ERROR ApexProfiling=NONE Callout=NONE Database=NONE System=NONE Validation=NONE Visualforce=NONE Workflow=NONE`,
      );
  const expires = new Date(now.getTime() + 12 * 3600 * 1000).toISOString();
  createToolingRecord(
    org,
    "TraceFlag",
    `TracedEntityId=${userId} DebugLevelId=${levelId} LogType=USER_DEBUG StartDate=${now.toISOString()} ExpirationDate=${expires}`,
  );
}

function logIds(org) {
  return sfJson(["apex", "list", "log", "-o", org]).map((log) => log.Id);
}

/** Runs a module's benchmark test class once and returns one run per size, read from the logs that run left. */
function measureTestRunOnce(org, testClass) {
  const before = new Set(logIds(org));
  const outcome = sfJson([
    "apex",
    "run",
    "test",
    "-o",
    org,
    "--tests",
    testClass,
    "--wait",
    "60",
  ]);
  if (outcome.summary.outcome !== "Passed") {
    const failed = outcome.tests
      .filter((test) => test.Outcome !== "Pass")
      .map((test) => `${test.MethodName}: ${test.Message}`);
    throw new Error(`${testClass} failed:\n${failed.join("\n")}`);
  }
  const runsBySize = new Map();
  for (const id of logIds(org).filter((each) => !before.has(each))) {
    const [log] = sfJson(["apex", "get", "log", "-o", org, "--log-id", id]);
    for (const line of (log.log ?? log).split("\n")) {
      if (line.includes(REPORT_PREFIX)) {
        const raw = reportIn(line);
        runsBySize.set(raw.records, publishedRun(raw));
      }
    }
  }
  const missing = RECORD_COUNTS.filter((size) => !runsBySize.has(size));
  if (missing.length) {
    throw new Error(
      `${testClass} passed but left no benchmark line for ${missing.join(", ")} records; is the org's user traced?`,
    );
  }
  return runsBySize;
}

/** Whether every run of a scenario handled all its records; only then is it published or compared. */
function isComplete(entry) {
  return entry.runs.every((run) => run.records_handled === entry.records);
}

/** Works out a scenario's kept values from its runs, or marks it incomplete and keeps only the runs. */
function summarize(module, records, runs) {
  if (!isComplete({ records, runs })) {
    return { module, records, complete: false, runs };
  }
  const medianRun = {};
  const largestRun = {};
  for (const measure of Object.keys(runs[0])) {
    const values = runs.map((run) => run[measure]);
    if (isLargestRunMeasure(measure)) {
      largestRun[measure] = Math.max(...values);
    } else {
      medianRun[measure] = median(values);
    }
  }
  return {
    module,
    records,
    complete: true,
    median: medianRun,
    largest: largestRun,
    runs,
  };
}

/** The value published for each measure: the median, or the largest run for heap. */
function kept(entry) {
  return { ...entry.median, ...entry.largest };
}

function median(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2
    ? sorted[middle]
    : (sorted[middle - 1] + sorted[middle]) / 2;
}

function consumerLines(module) {
  const count = (variant) =>
    fs
      .readdirSync(path.join(SCENARIOS_DIR, module))
      .filter((file) => file.startsWith(`${variant}.`))
      .map((file) =>
        fs.readFileSync(path.join(SCENARIOS_DIR, module, file), "utf8"),
      )
      .map((source) => source.replace(/\/\*[\s\S]*?\*\//g, ""))
      .flatMap((source) => source.split("\n"))
      .map((line) => line.replace(/\/\/.*$/, "").trim())
      .filter((line) => line.length > 0).length;
  return { forge: count("forge"), plain: count("plain") };
}

/** When a results file was run; a file from before run_at was recorded counts from the start of its date. */
function runTime(results) {
  return Date.parse(results.run_at ?? `${results.date}T00:00:00Z`);
}

/** The results files run before the given time, oldest first, leaving out the named file. */
function earlierResults(before, excludeFile) {
  if (!fs.existsSync(RESULTS_DIR)) {
    return [];
  }
  return fs
    .readdirSync(RESULTS_DIR)
    .filter((file) => file.endsWith(".json") && file !== excludeFile)
    .map((file) =>
      JSON.parse(fs.readFileSync(path.join(RESULTS_DIR, file), "utf8")),
    )
    .filter((results) => runTime(results) < before)
    .sort((a, b) => runTime(a) - runTime(b));
}

/** Whether an earlier results file published this module and size with every record handled. */
function publishedBefore(earlier, entry) {
  return earlier.some((results) =>
    results.results.some(
      (old) =>
        old.module === entry.module &&
        old.records === entry.records &&
        isComplete(old),
    ),
  );
}

/** Compares a scenario with the same scenario in the last published commit, re-run in the same org. */
function changesAgainst(earlier, baseline, entry, thresholds) {
  if (!entry.complete) {
    return { summary: NOT_PUBLISHED, regressions: [] };
  }
  if (!publishedBefore(earlier, entry)) {
    return { summary: "First published run", regressions: [] };
  }
  const before = baseline?.results.find(
    (old) => old.module === entry.module && old.records === entry.records,
  );
  if (!before?.complete) {
    return { summary: "Not compared", regressions: [], uncompared: true };
  }
  const regressions = [];
  const moves = [];
  const thresholdFor = (measure) =>
    CPU_MEASURES.includes(measure)
      ? thresholds.cpu_time
      : HEAP_MEASURES.includes(measure)
        ? thresholds.heap
        : thresholds.counts;
  for (const measure of [
    ...CPU_MEASURES,
    ...COUNT_MEASURES,
    ...HEAP_MEASURES,
  ]) {
    const was = kept(before)[measure];
    const now = kept(entry)[measure];
    if (was === now || was === undefined || now === undefined) {
      continue;
    }
    if (
      HEAP_MEASURES.includes(measure) &&
      Math.abs(now - was) < thresholds.heap_min_bytes
    ) {
      continue;
    }
    const change = was === 0 ? Infinity : (now - was) / was;
    if (Math.abs(change) > thresholdFor(measure)) {
      const percent = Number.isFinite(change)
        ? `${change > 0 ? "+" : ""}${Math.round(change * 100)}%`
        : `${was} -> ${now}`;
      moves.push(`${measure} ${percent}`);
      if (change > 0) {
        regressions.push(
          `${entry.module} ${entry.records}: ${measure} ${percent}`,
        );
      }
    }
  }
  return {
    summary: moves.length ? moves.join(", ") : "within thresholds",
    regressions,
  };
}

/** Compares every scenario of a run with its same-org baseline, and says which measures regressed and which sizes could not be compared. */
function compareWithBaseline(run, earlier, thresholds) {
  const changes = new Map();
  const regressions = [];
  const uncompared = [];
  for (const entry of run.results) {
    const change = changesAgainst(
      earlier,
      run.same_org_baseline,
      entry,
      thresholds,
    );
    changes.set(entry, change.summary);
    regressions.push(...change.regressions);
    if (change.uncompared) {
      uncompared.push(`${entry.module} ${entry.records}`);
    }
  }
  return { changes, regressions, uncompared };
}

/** The exit code of a run: a size that could not be compared fails first, because then nothing is published. */
function exitCodeFor(comparison, rebuild) {
  if (rebuild) {
    return 0;
  }
  if (comparison.uncompared.length) {
    return EXIT_UNCOMPARED;
  }
  return comparison.regressions.length ? EXIT_REGRESSION : 0;
}

/** The org's Id, which stays the same whatever alias the org is known by. */
function orgId(org) {
  const output = execFileSync("sf", ["org", "display", "-o", org, "--json"], {
    encoding: "utf8",
  });
  return JSON.parse(output).result.id;
}

/** The commit of the newest force-app change in this checkout. */
function checkedOutCommit() {
  return execFileSync(
    "git",
    ["-C", ROOT, "log", "-1", "--format=%h", "--", "force-app"],
    { encoding: "utf8" },
  ).trim();
}

/** Runs every scenario in the org and returns a new results file, with the time it was run and the org's Id. */
function measureInOrg(org, id, runs, commit, modules = MODULES) {
  const apiVersion = JSON.parse(
    fs.readFileSync(path.join(ROOT, "sfdx-project.json"), "utf8"),
  ).sourceApiVersion;
  const runAt = new Date().toISOString();
  const results = [];
  if (modules.some((module) => TEST_CLASS_MODULES[module])) {
    traceTheRunningUser(org);
  }
  for (const module of modules) {
    const testClass = TEST_CLASS_MODULES[module];
    if (testClass) {
      const measured = [];
      for (let run = 1; run <= runs; run++) {
        process.stderr.write(`${module} (${testClass}) run ${run}/${runs}\n`);
        measured.push(measureTestRunOnce(org, testClass));
      }
      for (const records of RECORD_COUNTS) {
        const bySize = measured.map((runsBySize) => runsBySize.get(records));
        results.push(summarize(module, records, bySize));
      }
      continue;
    }
    for (const records of RECORD_COUNTS) {
      const measured = [];
      for (let run = 1; run <= runs; run++) {
        process.stderr.write(`${module} ${records} run ${run}/${runs}\n`);
        measured.push(measureOnce(org, module, records));
      }
      results.push(summarize(module, records, measured));
    }
  }
  const lines = {};
  for (const module of modules) {
    lines[module] = consumerLines(module);
  }
  return {
    date: runAt.slice(0, 10),
    run_at: runAt,
    commit,
    org_id: id,
    api_version: apiVersion,
    runs,
    results,
    consumer_lines: lines,
  };
}

/** Reads a results file and works its kept values out again from the runs in it. */
function rebuilt(file) {
  const old = JSON.parse(fs.readFileSync(file, "utf8"));
  const resummarized = (entries) =>
    entries.map((entry) => summarize(entry.module, entry.records, entry.runs));
  return {
    date: old.date,
    ...(old.run_at && { run_at: old.run_at }),
    commit: old.commit,
    ...(old.org_id && { org_id: old.org_id }),
    api_version: old.api_version,
    runs: old.runs,
    results: resummarized(old.results),
    consumer_lines: old.consumer_lines,
    ...(old.same_org_baseline && {
      same_org_baseline: {
        ...old.same_org_baseline,
        results: resummarized(old.same_org_baseline.results),
      },
    }),
  };
}

/** Where an org's --baseline pass is kept: under the org's Id, so every alias of the same org finds it. */
function sameOrgFile(id) {
  return path.join(SAME_ORG_DIR, `${id}.json`);
}

/** Runs the last published commit in the org as the --baseline pass, and keeps it for the change's pass. */
function measureSameOrgBaseline(org, runs, lastPublished) {
  if (!lastPublished) {
    throw new Error(
      "Nothing is published yet, so there is no baseline to re-run.",
    );
  }
  const id = orgId(org);
  process.stderr.write(
    `Measuring ${org} (${id}) as ${lastPublished.commit}, the last published commit.\n`,
  );
  // A module the last published run lacks is not in that commit's force-app either.
  const publishedModules = MODULES.filter((module) =>
    lastPublished.results.some((entry) => entry.module === module),
  );
  const rerun = measureInOrg(
    org,
    id,
    runs,
    lastPublished.commit,
    publishedModules,
  );
  fs.mkdirSync(SAME_ORG_DIR, { recursive: true });
  fs.writeFileSync(sameOrgFile(id), JSON.stringify(rerun, null, 2) + "\n");
  printTables(rerun, (entry) =>
    entry.complete ? "same-org baseline" : NOT_PUBLISHED,
  );
  printWarnings(rerun.results);
  console.log(
    `\nSame-org baseline: perf/.same-org/${id}.json. Now deploy the change and run without --baseline.`,
  );
}

/** Reads the org's --baseline pass, refused unless it re-ran the last published commit in this org. */
function sameOrgBaseline(org, id, lastPublished) {
  const file = sameOrgFile(id);
  if (!fs.existsSync(file)) {
    throw new Error(
      `No same-org baseline for ${org} (${id}). Deploy force-app at ${lastPublished.commit} and run with --baseline first.`,
    );
  }
  return checkedSameOrgBaseline(
    JSON.parse(fs.readFileSync(file, "utf8")),
    id,
    lastPublished,
  );
}

/** Returns the baseline pass if it was measured in the org with this Id at the last published commit, and throws otherwise. */
function checkedSameOrgBaseline(baseline, id, lastPublished) {
  if (baseline.org_id !== id) {
    throw new Error(
      `The baseline was measured in org ${baseline.org_id ?? "(not recorded)"}, not in ${id}. Run --baseline again in this org.`,
    );
  }
  if (baseline.commit !== lastPublished.commit) {
    throw new Error(
      `The baseline for ${id} is ${baseline.commit}, but the last published run is ${lastPublished.commit}. Run --baseline again at ${lastPublished.commit}.`,
    );
  }
  return baseline;
}

/** Prints each module's README table; changeFor returns the text of the Change column for one scenario. */
function printTables(run, changeFor) {
  const modules = MODULES.filter((module) =>
    run.results.some((entry) => entry.module === module),
  );
  for (const module of modules) {
    console.log(
      `\n## ${module}\n\n_Run: ${run.date}, ${run.commit}, API ${run.api_version}_\n`,
    );
    console.log(
      "| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change |",
    );
    console.log("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const entry of run.results.filter((each) => each.module === module)) {
      const change = changeFor(entry);
      if (!entry.complete) {
        console.log(`| ${entry.records} | | | | | | | | ${change} |`);
        continue;
      }
      const m = kept(entry);
      console.log(
        `| ${entry.records} | ${m.cpu_time_ms} | ${m.heap_bytes} | ${m.soql_queries} | ${m.query_rows} | ${m.dml_statements} | ${m.dml_rows} | ${m.wall_time_ms} | ${change} |`,
      );
    }
    printJobTables(
      run.results.filter(
        (each) => each.module === module && kept(each).jobs_run !== undefined,
      ),
    );
    console.log(
      `\nConsumer lines: ${run.consumer_lines[module].forge} (forge) / ${run.consumer_lines[module].plain} (plain)`,
    );
  }
}

/** Prints the queued jobs' table and the field-query table for a module whose save queues jobs. */
function printJobTables(entries) {
  if (!entries.length) {
    return;
  }
  console.log(
    "\n| Records | Callouts in save | Jobs queued | Jobs run | Callouts per job | Job CPU ms | Job SOQL | Job query rows | Job DML | Failures |",
  );
  console.log("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
  for (const entry of entries) {
    const m = kept(entry);
    console.log(
      `| ${entry.records} | ${m.callouts} | ${m.jobs_queued} | ${m.jobs_run} | ${m.job_callouts} | ${m.job_cpu_time_ms} | ${m.job_soql_queries} | ${m.job_query_rows} | ${m.job_dml_statements} | ${m.failures} |`,
    );
  }
  console.log(
    "\n| Records read by one job | Readable fields | Every-field query CPU ms | Heap | Only-used-fields query CPU ms | Heap |",
  );
  console.log("| --- | --- | --- | --- | --- | --- |");
  for (const entry of entries) {
    const m = kept(entry);
    console.log(
      `| ${Math.min(entry.records, 200)} | ${m.readable_fields} | ${m.field_query_cpu_time_ms} | ${m.field_query_heap_bytes} | ${m.used_fields_query_cpu_time_ms} | ${m.used_fields_query_heap_bytes} |`,
    );
  }
}

function printWarnings(results) {
  const incomplete = results.filter((entry) => !entry.complete);
  if (incomplete.length) {
    console.log(
      "\nNot published or compared, because a run did not handle every record:",
    );
    for (const entry of incomplete) {
      const handled = entry.runs.map((each) => each.records_handled);
      const short = handled.filter((count) => count !== entry.records);
      console.log(
        `- ${entry.module} ${entry.records}: ${short.length} of ${handled.length} runs short (handled ${handled.join(", ")})`,
      );
    }
  }
  const uncountedHeap = results.filter((entry) => {
    const single = results.find(
      (each) => each.module === entry.module && each.records === 1,
    );
    return (
      entry.records > 1 &&
      entry.complete &&
      single?.complete &&
      entry.largest.heap_bytes <= single.largest.heap_bytes
    );
  });
  if (uncountedHeap.length) {
    console.log(
      "\nHeap no larger than at 1 record, so every run probably left records out; run again:",
    );
    for (const entry of uncountedHeap) {
      console.log(
        `- ${entry.module} ${entry.records}: ${entry.largest.heap_bytes} bytes`,
      );
    }
  }
}

/** Prints a run's tables and findings, and writes its results file unless it is withheld. */
function report(run, comparison, withheld) {
  printTables(run, (entry) => comparison.changes.get(entry));
  if (run.same_org_baseline) {
    console.log(
      `\nCompared with ${run.same_org_baseline.commit}, re-run in the same org at ${run.same_org_baseline.run_at}.`,
    );
  }
  printWarnings(run.results);
  if (comparison.uncompared.length) {
    console.log(
      `\nNot compared, because the same-org re-run did not handle every record; run --baseline again:\n- ${comparison.uncompared.join("\n- ")}`,
    );
  }
  if (comparison.regressions.length) {
    console.log(
      `\nRegressions over threshold:\n- ${comparison.regressions.join("\n- ")}`,
    );
  }
  const resultsFile = `${run.date}-${run.commit}.json`;
  if (withheld) {
    console.log(
      `\nNot written to docs/performance/results/${resultsFile}, because a size published before was not compared.`,
    );
    return;
  }
  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(RESULTS_DIR, resultsFile),
    JSON.stringify(run, null, 2) + "\n",
  );
  console.log(`\nResults: docs/performance/results/${resultsFile}`);
}

function main() {
  const { org, rebuild, baseline, runs } = readArguments();
  const thresholds = {
    ...DEFAULT_THRESHOLDS,
    ...(fs.existsSync(THRESHOLDS_FILE)
      ? JSON.parse(fs.readFileSync(THRESHOLDS_FILE, "utf8"))
      : {}),
  };
  const lastPublished = earlierResults(Date.now()).at(-1);
  if (baseline) {
    measureSameOrgBaseline(org, runs, lastPublished);
    return;
  }

  // Check for the same-org baseline before spending time in the org.
  const id = rebuild ? undefined : orgId(org);
  const sameOrg =
    !rebuild && lastPublished && sameOrgBaseline(org, id, lastPublished);
  const run = rebuild
    ? rebuilt(rebuild)
    : measureInOrg(org, id, runs, checkedOutCommit());
  if (sameOrg) {
    run.same_org_baseline = sameOrg;
  }
  // Read the earlier files before writing, so an earlier run of the same commit on the
  // same date is still a baseline before its file is replaced. A rebuild is never its
  // own baseline.
  const earlier = earlierResults(
    runTime(run),
    rebuild ? path.basename(rebuild) : undefined,
  );
  const comparison = compareWithBaseline(run, earlier, thresholds);
  process.exitCode = exitCodeFor(comparison, rebuild);
  report(run, comparison, process.exitCode === EXIT_UNCOMPARED);
}

if (require.main === module) {
  main();
}

module.exports = {
  checkedSameOrgBaseline,
  compareWithBaseline,
  exitCodeFor,
  EXIT_REGRESSION,
  EXIT_UNCOMPARED,
  publishedRun,
  summarize,
};
