# Benchmarks

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
- `run-benchmarks.js` runs every scenario five times, one anonymous Apex
  transaction per run, keeps the median, writes
  `docs/performance/results/<date>-<commit>.json` and prints the README rows, the
  change against the previous results file and any measure over
  `thresholds.json`.

```bash
sf org create scratch -f config/project-scratch-def.json --target-dev-hub <dev-hub> --alias <org> -y 1
sf project deploy start -o <org> --source-dir force-app --source-dir perf/benchmarks
node perf/run-benchmarks.js --org <org>
sf org delete scratch -o <org> --no-prompt
```

The trigger handler scenario puts a trigger on Lead, so deploy `perf/benchmarks`
only to a scratch org made for benchmarking.
