/**
 * Runs every module's benchmark in a scratch org, keeps the median of five runs (the
 * largest for heap) and writes the results file and the README tables' rows.
 *
 *   node perf/run-benchmarks.js --org <scratch-org-alias> [--runs 5]
 *   node perf/run-benchmarks.js --rebuild docs/performance/results/<file>.json
 *
 * The org must already have force-app and perf/benchmarks deployed. Each run is one
 * anonymous Apex transaction, so every measurement starts with fresh limits.
 * --rebuild needs no org: it works the kept values out again from the runs already in
 * a results file, and rewrites it.
 */
const { execFileSync } = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const ROOT = path.resolve(__dirname, "..");
const RESULTS_DIR = path.join(ROOT, "docs", "performance", "results");
const THRESHOLDS_FILE = path.join(ROOT, "perf", "thresholds.json");
const SCENARIOS_DIR = path.join(ROOT, "perf", "scenarios");
const REPORT_PREFIX = "FORGE_BENCHMARK ";

const DEFAULT_THRESHOLDS = { cpu_time: 0.1, governor: 0.1 };

const MODULES = ["trigger-handler", "data-builder"];
const RECORD_COUNTS = [1, 200, 2000];

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
// is the median, under "median". All five runs can still read low.
const LARGEST_RUN_MEASURES = ["heap_bytes"];
const CPU_MEASURES = ["cpu_time_ms"];
const GOVERNOR_MEASURES = [
  "soql_queries",
  "query_rows",
  "dml_statements",
  "dml_rows",
  "heap_bytes",
];
const NOT_PUBLISHED = "Not published yet";

function readArguments() {
  const args = process.argv.slice(2);
  const valueOf = (flag) => {
    const at = args.indexOf(flag);
    return at === -1 ? undefined : args[at + 1];
  };
  const org = valueOf("--org");
  const rebuild = valueOf("--rebuild");
  if (!org === !rebuild) {
    throw new Error(
      "Usage: node perf/run-benchmarks.js --org <alias> | --rebuild <results file>",
    );
  }
  return { org, rebuild, runs: Number(valueOf("--runs") ?? 5) };
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
  const raw = JSON.parse(
    line.slice(line.indexOf(REPORT_PREFIX) + REPORT_PREFIX.length),
  );
  const run = {};
  for (const [apexName, publishedName] of Object.entries(MEASURES)) {
    run[publishedName] = raw[apexName];
  }
  return run;
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
  for (const measure of Object.values(MEASURES)) {
    const values = runs.map((run) => run[measure]);
    if (LARGEST_RUN_MEASURES.includes(measure)) {
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

/** The latest complete result for the same module and size among earlier results files. */
function baselineFor(earlier, entry) {
  for (const results of [...earlier].reverse()) {
    const before = results.results.find(
      (old) => old.module === entry.module && old.records === entry.records,
    );
    if (before && isComplete(before)) {
      return before;
    }
  }
  return undefined;
}

function changesAgainst(earlier, entry, thresholds) {
  if (!entry.complete) {
    return { summary: NOT_PUBLISHED, regressions: [] };
  }
  const before = baselineFor(earlier, entry);
  if (!before) {
    return { summary: "First published run", regressions: [] };
  }
  const regressions = [];
  const moves = [];
  const limitFor = (measure) =>
    CPU_MEASURES.includes(measure)
      ? thresholds.cpu_time
      : GOVERNOR_MEASURES.includes(measure)
        ? thresholds.governor
        : null;
  for (const measure of [...CPU_MEASURES, ...GOVERNOR_MEASURES]) {
    const was = kept(before)[measure];
    const now = kept(entry)[measure];
    if (was === now) {
      continue;
    }
    const change = was === 0 ? Infinity : (now - was) / was;
    if (Math.abs(change) > limitFor(measure)) {
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

/** Runs every scenario in the org and returns a new results file, with the time it was run. */
function measureInOrg(org, runs) {
  const commit = execFileSync(
    "git",
    ["-C", ROOT, "log", "-1", "--format=%h", "--", "force-app"],
    { encoding: "utf8" },
  ).trim();
  const apiVersion = JSON.parse(
    fs.readFileSync(path.join(ROOT, "sfdx-project.json"), "utf8"),
  ).sourceApiVersion;
  const runAt = new Date().toISOString();
  const results = [];
  for (const module of MODULES) {
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
  for (const module of MODULES) {
    lines[module] = consumerLines(module);
  }
  return {
    date: runAt.slice(0, 10),
    run_at: runAt,
    commit,
    api_version: apiVersion,
    runs,
    results,
    consumer_lines: lines,
  };
}

/** Reads a results file and works its kept values out again from the runs in it. */
function rebuilt(file) {
  const old = JSON.parse(fs.readFileSync(file, "utf8"));
  return {
    date: old.date,
    ...(old.run_at && { run_at: old.run_at }),
    commit: old.commit,
    api_version: old.api_version,
    runs: old.runs,
    results: old.results.map((entry) =>
      summarize(entry.module, entry.records, entry.runs),
    ),
    consumer_lines: old.consumer_lines,
  };
}

function main() {
  const { org, rebuild, runs } = readArguments();
  const thresholds = fs.existsSync(THRESHOLDS_FILE)
    ? JSON.parse(fs.readFileSync(THRESHOLDS_FILE, "utf8"))
    : DEFAULT_THRESHOLDS;
  const run = rebuild ? rebuilt(rebuild) : measureInOrg(org, runs);
  const resultsFile = `${run.date}-${run.commit}.json`;
  // Read the earlier files before writing, so an earlier run of the same commit on the
  // same date is still a baseline before its file is replaced. A rebuild is never its
  // own baseline.
  const earlier = earlierResults(
    runTime(run),
    rebuild ? path.basename(rebuild) : undefined,
  );

  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(RESULTS_DIR, resultsFile),
    JSON.stringify(run, null, 2) + "\n",
  );

  const { results, consumer_lines: lines } = run;
  const regressions = [];
  for (const module of MODULES) {
    console.log(
      `\n## ${module}\n\n_Run: ${run.date}, ${run.commit}, API ${run.api_version}_\n`,
    );
    console.log(
      "| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change |",
    );
    console.log("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const entry of results.filter((each) => each.module === module)) {
      const change = changesAgainst(earlier, entry, thresholds);
      regressions.push(...change.regressions);
      if (!entry.complete) {
        console.log(`| ${entry.records} | | | | | | | | ${change.summary} |`);
        continue;
      }
      const m = kept(entry);
      console.log(
        `| ${entry.records} | ${m.cpu_time_ms} | ${m.heap_bytes} | ${m.soql_queries} | ${m.query_rows} | ${m.dml_statements} | ${m.dml_rows} | ${m.wall_time_ms} | ${change.summary} |`,
      );
    }
    console.log(
      `\nConsumer lines: ${lines[module].forge} (forge) / ${lines[module].plain} (plain)`,
    );
  }
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
  console.log(`\nResults: docs/performance/results/${resultsFile}`);
  if (regressions.length) {
    console.log(`\nRegressions over threshold:\n- ${regressions.join("\n- ")}`);
    process.exitCode = 2;
  }
}

main();
