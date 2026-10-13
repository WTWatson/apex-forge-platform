# Performance

This page shows what each part of the platform costs when your code uses it: how
much CPU time, memory, queries and DML it spends in a transaction. Salesforce caps
all of these per transaction (the governor limits), so before you adopt a module you
can see how much of your budget it takes. Because every change is measured the same
way, the tables also show whether a change made the platform slower.

## How to read the tables

Each module has one table. Each row is one run of the module on a number of records:
1, 200 (one trigger batch) and, where the module can handle it, 2,000.

| Column | What it means |
| --- | --- |
| CPU ms | Apex CPU time used, in milliseconds. The limit is 10,000 in a normal transaction. |
| Heap | Memory used, in bytes. The limit is 6 MB in a normal transaction. |
| SOQL | Number of queries run. The limit is 100. |
| Query rows | Records those queries returned. The limit is 50,000. |
| DML | Number of insert, update or delete statements. The limit is 150. |
| DML rows | Records those statements wrote. The limit is 10,000. |
| Wall ms | Elapsed time, in milliseconds, as a rough guide only. It varies with the org's load. |
| Change | The difference from the previous published run. |

Under each table, **consumer lines** compares the Apex you write for one everyday
task with the platform and without it, in plain Apex. Blank lines and comments are
not counted. Both versions are in `perf/scenarios/<module>/`, so you can read them
side by side.

## How the numbers are measured

- A benchmark drives the module's public methods the way your code would.
- Each module is measured in its own fresh scratch org, five times. The table shows
  the middle (median) value, so one slow run doesn't skew it.
- The raw numbers of every run, all five values included, are in
  `docs/performance/results/<date>-<commit>.json`.

## When a change counts as slower

If a change makes CPU time, or any of the governor measures (heap, queries, query
rows, DML statements, DML rows), more than 10% worse than the last published run,
it is treated as a regression. It must be fixed or explained before it is merged.
The limits are set in `perf/thresholds.json`. Wall time is shown but is not checked.
Faster numbers are reported too.

## Trigger handler framework

_Run: (date), (commit), API (version)_

| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | | | | | | | | |
| 200 | | | | | | | | |
| 2000 | | | | | | | | |

Consumer lines: (with the platform) / (plain Apex)

## Data builder and seeder

_Run: (date), (commit), API (version)_

| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | | | | | | | | |
| 200 | | | | | | | | |
| 2000 | | | | | | | | |

Consumer lines: (with the platform) / (plain Apex)
