# Benchmarks

The benchmarks exist so every change to the platform is measured the same way, and
its cost is published with it.

Each platform module has a benchmark that drives its public API the way a consumer
would, at 1, 200 and 2,000 records. The published numbers are in
`docs/performance/`.

- `benchmarks/` is Apex source deployed beside `force-app` in a scratch org only:
  `ForgeBenchmark` measures a scenario inside a savepoint and rolls it back, one
  `<Module>Benchmark` class per module sets up and performs the scenario, and the
  consumer classes they call (`LeadRatingHandler` with `LeadTrigger`,
  `CustomerSeed`) are the same code as the module's `forge` sample.
  `ForgeAccessBenchmark` holds both of its module's controllers, the `forge` and the
  `plain` sample, as inner classes.
- `scenarios/<module>/` holds the paired consumer samples: `forge.*` is the code a
  developer writes with the platform, `plain.*` the plain-Apex equivalent. Consumer
  lines are the non-blank, non-comment lines of each side.
- `run-benchmarks.js` runs every scenario five times, each run in its own
  anonymous Apex transaction. It keeps the median of each measure, except heap,
  where it keeps the largest run; `docs/performance/README.md` says why. It writes
  the five runs and the kept values to
  `docs/performance/results/<date>-<commit>.json` and prints the README rows.
- A module that works only inside a test, such as `forge-http` with its HTTP mock
  and Account test trigger, is benchmarked by a test class instead: one test run
  measures every size, and the runner reads each size's numbers from the debug
  log the run leaves. Before the first test run it traces the org's user at the
  `ForgeBenchmark` debug level, which it creates if the org has none.
- A test class can measure other scenarios beside the module's main one, each
  test method writing one line that names its scenario. `ForgeAccessBenchmark`
  measures the plain-Apex controller beside ForgeAccess's (`plain`), and the save
  of records that hold only an Id and the changed field with each (`table-save`,
  `plain-table-save`). Their measures are published with the scenario's name in
  front, such as `table_save_cpu_time_ms`, and the runner prints a table for each.
  The table save runs platform code, so it is checked against the thresholds like
  the main scenario; the plain-Apex scenarios are published to compare with and
  are not checked. A size is published only if every scenario handled all its
  records.
- A scenario where any run handled fewer records than it was given is not
  published or compared. Its runs stay in the results file, marked
  `"complete": false`.
- `node perf/run-benchmarks.js --rebuild <results file>` works the kept values out
  again from the runs already in a results file. It needs no org.

## Comparing a change in one org

CPU time differs from one scratch org to the next by more than a real slowdown
would, so a change is never compared with numbers from another org. Instead both
versions run in the same org, one after the other:

1. Deploy `force-app` as it was at the last published commit (the `commit` of the
   newest file in `docs/performance/results/`), with `perf/benchmarks`, and run
   `node perf/run-benchmarks.js --org <org> --baseline`. This measures the old
   code and keeps it in `perf/.same-org/<org Id>.json`, which is not committed.
   The runner reads the org's Id with `sf org display`, so any alias of the same
   org finds that file, and an alias that now names another org does not. It
   measures only the modules the last published run has: remove the benchmark
   class of any newer module from the copy, since its module is not in the old
   `force-app`. A module published for the first time is marked "First published
   run" in step 2, with nothing to compare against.
2. Deploy the change's `force-app` to the same org and run
   `node perf/run-benchmarks.js --org <org>`. It refuses to start if step 1 is
   missing, was run in another org or was run on another commit. It compares
   every measure with step 1, writes the results file with step 1's numbers in it
   under `same_org_baseline`, and lists every measure over `thresholds.json`. If
   any is over, it exits with code 2.
3. If step 1 did not measure a size that was published before, or did not handle
   every record of it, the change cannot be compared at that size. Then the runner
   writes no results file and exits with code 3; run both steps again.

`npm run test:perf` checks the comparison with canned results, with no org.

`thresholds.json` allows CPU time 25% and the counts (queries, query rows, DML
statements, DML rows) 10%. Heap is allowed 10%, but a change smaller than 512
bytes is never counted. `docs/performance/README.md` says why.

```bash
sf org create scratch -f config/project-scratch-def.json --target-dev-hub <dev-hub> --alias <org> -y 1

# Step 1: the last published commit, from a copy outside the worktree. Deploy it
# from inside the copy: sf's source tracking breaks on paths outside the project.
# The copy needs every folder its sfdx-project.json lists, test-support included.
# Add --ignore-conflicts when the org already has newer versions of these files.
mkdir -p <dir> && git archive <last-published-commit> force-app test-support sfdx-project.json | tar -x -C <dir>
cp -r perf/benchmarks <dir>/
rm <dir>/benchmarks/classes/<NewModule>Benchmark.cls*   # each module newer than that commit
cd <dir>
sf project deploy start -o <org> --source-dir force-app --source-dir benchmarks
cd -
node perf/run-benchmarks.js --org <org> --baseline

# Step 2: the change, over the files step 1 deployed
sf project deploy start -o <org> --source-dir force-app --source-dir test-support --source-dir perf/benchmarks --ignore-conflicts
node perf/run-benchmarks.js --org <org>

sf org delete scratch -o <org> --no-prompt
```

The trigger handler scenario puts a trigger on Lead and `test-support` puts one on
Account, so deploy `perf/benchmarks` and `test-support` only to a scratch org made
for benchmarking.
