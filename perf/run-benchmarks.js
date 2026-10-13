/**
 * Runs every module's benchmark in a scratch org, keeps the median of five runs and
 * writes the results file and the README tables' rows.
 *
 *   node perf/run-benchmarks.js --org <scratch-org-alias> [--runs 5]
 *
 * The org must already have force-app and perf/benchmarks deployed. Each run is one
 * anonymous Apex transaction, so every measurement starts with fresh limits.
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
const CPU_MEASURES = ["cpu_time_ms"];
const GOVERNOR_MEASURES = [
  "soql_queries",
  "query_rows",
  "dml_statements",
  "dml_rows",
  "heap_bytes",
];

function readArguments() {
  const args = process.argv.slice(2);
  const valueOf = (flag) => {
    const at = args.indexOf(flag);
    return at === -1 ? undefined : args[at + 1];
  };
  const org = valueOf("--org");
  if (!org) {
    throw new Error("Usage: node perf/run-benchmarks.js --org <alias>");
  }
  return { org, runs: Number(valueOf("--runs") ?? 5) };
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

function previousResults(excludeFile) {
  if (!fs.existsSync(RESULTS_DIR)) {
    return null;
  }
  const files = fs
    .readdirSync(RESULTS_DIR)
    .filter((file) => file.endsWith(".json") && file !== excludeFile)
    .sort();
  return files.length
    ? JSON.parse(
        fs.readFileSync(
          path.join(RESULTS_DIR, files[files.length - 1]),
          "utf8",
        ),
      )
    : null;
}

function changesAgainst(previous, entry, thresholds) {
  const before = previous?.results.find(
    (old) => old.module === entry.module && old.records === entry.records,
  );
  if (!before) {
    return { summary: "first baseline", regressions: [] };
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
    const was = before.median[measure];
    const now = entry.median[measure];
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

function main() {
  const { org, runs } = readArguments();
  const commit = execFileSync(
    "git",
    ["-C", ROOT, "log", "-1", "--format=%h", "--", "force-app"],
    { encoding: "utf8" },
  ).trim();
  const apiVersion = JSON.parse(
    fs.readFileSync(path.join(ROOT, "sfdx-project.json"), "utf8"),
  ).sourceApiVersion;
  const date = new Date().toISOString().slice(0, 10);
  const resultsFile = `${date}-${commit}.json`;
  const thresholds = fs.existsSync(THRESHOLDS_FILE)
    ? JSON.parse(fs.readFileSync(THRESHOLDS_FILE, "utf8"))
    : DEFAULT_THRESHOLDS;
  const previous = previousResults(resultsFile);

  const results = [];
  for (const module of MODULES) {
    for (const records of RECORD_COUNTS) {
      const measured = [];
      for (let run = 1; run <= runs; run++) {
        process.stderr.write(`${module} ${records} run ${run}/${runs}\n`);
        measured.push(measureOnce(org, module, records));
      }
      const medianRun = {};
      for (const measure of Object.values(MEASURES)) {
        medianRun[measure] = median(measured.map((run) => run[measure]));
      }
      results.push({ module, records, median: medianRun, runs: measured });
    }
  }

  const lines = {};
  for (const module of MODULES) {
    lines[module] = consumerLines(module);
  }

  fs.mkdirSync(RESULTS_DIR, { recursive: true });
  fs.writeFileSync(
    path.join(RESULTS_DIR, resultsFile),
    JSON.stringify(
      {
        date,
        commit,
        api_version: apiVersion,
        runs,
        results,
        consumer_lines: lines,
      },
      null,
      2,
    ) + "\n",
  );

  const regressions = [];
  for (const module of MODULES) {
    console.log(
      `\n## ${module}\n\n_Run: ${date}, ${commit}, API ${apiVersion}_\n`,
    );
    console.log(
      "| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change |",
    );
    console.log("| --- | --- | --- | --- | --- | --- | --- | --- | --- |");
    for (const entry of results.filter((each) => each.module === module)) {
      const m = entry.median;
      const change = changesAgainst(previous, entry, thresholds);
      regressions.push(...change.regressions);
      console.log(
        `| ${entry.records} | ${m.cpu_time_ms} | ${m.heap_bytes} | ${m.soql_queries} | ${m.query_rows} | ${m.dml_statements} | ${m.dml_rows} | ${m.wall_time_ms} | ${change.summary} |`,
      );
    }
    console.log(
      `\nConsumer lines: ${lines[module].forge} (forge) / ${lines[module].plain} (plain)`,
    );
  }
  const shortfalls = results.filter(
    (entry) => entry.median.records_handled !== entry.records,
  );
  if (shortfalls.length) {
    console.log("\nScenarios that did not handle every record:");
    for (const entry of shortfalls) {
      console.log(
        `- ${entry.module} ${entry.records}: ${entry.median.records_handled} handled`,
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
