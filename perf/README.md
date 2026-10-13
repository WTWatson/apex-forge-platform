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
- `scenarios/<module>/` holds the paired consumer samples: `forge.*` is the code a
  developer writes with the platform, `plain.*` the plain-Apex equivalent. Consumer
  lines are the non-blank, non-comment lines of each side.
- `run-benchmarks.js` runs every scenario five times, each run in its own
  anonymous Apex transaction. It keeps the median of each measure, except heap,
  where it keeps the largest run; `docs/performance/README.md` says why. It writes
  the five runs and the kept values to
  `docs/performance/results/<date>-<commit>.json` and prints the README rows.
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
   code and keeps it in `perf/.same-org/<org>.json`, which is not committed.
2. Deploy the change's `force-app` to the same org and run
   `node perf/run-benchmarks.js --org <org>`. It refuses to start if step 1 is
   missing or was run on another commit. It compares every measure with step 1,
   writes the results file with step 1's numbers in it under `same_org_baseline`,
   and lists every measure over `thresholds.json`. If any is over, it exits with
   code 2.

`thresholds.json` allows CPU time 25% and the counts (queries, query rows, DML
statements, DML rows) 10%. Heap is allowed 10%, but a change smaller than 512
bytes is never counted. `docs/performance/README.md` says why.

```bash
sf org create scratch -f config/project-scratch-def.json --target-dev-hub <dev-hub> --alias <org> -y 1

# Step 1: the last published commit, from a copy outside the worktree
mkdir -p <dir> && git archive <last-published-commit> force-app sfdx-project.json | tar -x -C <dir>
cp -r perf/benchmarks <dir>/
cd <dir>
sf project deploy start -o <org> --source-dir force-app --source-dir benchmarks
cd -
node perf/run-benchmarks.js --org <org> --baseline

# Step 2: the change
sf project deploy start -o <org> --source-dir force-app --source-dir perf/benchmarks
node perf/run-benchmarks.js --org <org>

sf org delete scratch -o <org> --no-prompt
```

The trigger handler scenario puts a trigger on Lead, so deploy `perf/benchmarks`
only to a scratch org made for benchmarking.
