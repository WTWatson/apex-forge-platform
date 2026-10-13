# Performance

Every module of the platform is benchmarked by driving its public API the way a
consumer would, at 1, 200 and (where the module allows) 2,000 records, in one fresh
scratch org, five runs, the median kept. The raw numbers of every run are in
`results/<date>-<sha>.json`; the thresholds that make a change a regression are in
`../../perf/thresholds.json`. The paired consumer samples (the platform versus
plain Apex, same scenario) are in `../../perf/scenarios/<module>/`.

Columns: CPU time (ms), heap (bytes), SOQL queries, query rows, DML statements, DML
rows, wall time (ms); the change column is against the previous published run.
Consumer lines is the non-blank, non-comment Apex a developer writes for the
module's scenario, with the platform and in plain Apex.

## Trigger handler framework

_Run: (date), (commit), API (version)_

| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | | | | | | | | |
| 200 | | | | | | | | |
| 2000 | | | | | | | | |

Consumer lines: (forge) / (plain)

## Data builder and seeder

_Run: (date), (commit), API (version)_

| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | | | | | | | | |
| 200 | | | | | | | | |
| 2000 | | | | | | | | |

Consumer lines: (forge) / (plain)
