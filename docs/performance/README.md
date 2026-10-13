# Performance

This page shows what each part of the platform costs when your code uses it: how
much CPU time, memory, queries and DML it spends in a transaction. Salesforce caps
all of these per transaction (the governor limits), so before you adopt a module you
can see how much of your budget it takes. Because every change is measured the same
way, the tables also show whether a change made the platform slower.

## How to read the tables

Each module has one table. Each row is one run of the module on a number of records:
1, 200 (one trigger batch) and, where the module can handle it, 2,000.

| Column     | What it means                                                                        |
| ---------- | ------------------------------------------------------------------------------------ |
| CPU ms     | Apex CPU time used, in milliseconds. The limit is 10,000 in a normal transaction.    |
| Heap       | Memory the measured call added, in bytes. The limit is 6 MB in a normal transaction. |
| SOQL       | Number of queries run. The limit is 100.                                             |
| Query rows | Records those queries returned. The limit is 50,000.                                 |
| DML        | Number of insert, update or delete statements. The limit is 150.                     |
| DML rows   | Records those statements wrote. The limit is 10,000.                                 |
| Wall ms    | Elapsed time, in milliseconds, as a rough guide only. It varies with the org's load. |
| Change     | The difference from the previous published version, run again in the same org.       |

Under each table, **consumer lines** compares the Apex you write for one everyday
task with the platform and without it, in plain Apex. Blank lines and comments are
not counted. Both versions are in `perf/scenarios/<module>/`, so you can read them
side by side.

## How the numbers are measured

- A benchmark drives the module's public methods the way your code would.
- Each version is measured in a fresh scratch org, five times. The table shows the
  middle (median) value, so one slow run doesn't skew it.
- CPU time differs between scratch orgs: the same data builder code at 200 records
  measured 14% slower in a new org than in the one before. So a change is never
  compared with numbers from another org. The previous published version is deployed to the same org and
  measured first, then the change is deployed and measured, and the Change column
  compares the two. The results file keeps the previous version's numbers from that
  org under `same_org_baseline`.
- Heap is the memory the measured call added: the heap just after the call minus
  the heap just before it. Records the benchmark builds before the call are not in
  it, and neither is memory the call uses and frees again.
- For heap the table shows the largest of the five runs, not the median. Salesforce
  sometimes counts less memory than a run holds, and has not been seen to count
  more. Even the largest run can read low, if all five were counted short.
- A size is published only if every run handled all its records. Otherwise its row
  reads "Not published yet" and it is not compared with any other run.
- Each run's results file, `docs/performance/results/<date>-<commit>.json`, keeps
  all five runs under `runs`, and the published value of each measure under
  `median` (heap under `largest`). A size that is not published is marked
  `"complete": false` and keeps only its runs.

## When a change counts as slower

A change counts as a regression when, compared with the previous version in the
same org, it is worse by more than:

- **25% CPU time.** Five runs of the same code in one org have ranged from 444 to
  712 ms, so a smaller limit would flag unchanged code.
- **10% queries, query rows, DML statements or DML rows.** These are exact counts:
  the same code gives the same number every time.
- **10% heap, counting only changes of 512 bytes or more.** At 200 and 2,000
  records the same code's heap repeats within half a percent, so 10% catches real
  growth. At 1 record the readings are small (about 450 bytes for the trigger
  handler) and the same code has read up to 63 bytes apart between orgs, more than
  10% of it. The 512-byte floor keeps that noise from counting.

A regression must be fixed or explained before it is merged. The limits are set
in `perf/thresholds.json`. Wall time is shown but is not checked. Faster numbers
are reported too.

## Trigger handler framework

_Run: 2026-10-13, e2a5cf0, API 66.0_

| Records | CPU ms | Heap | SOQL | Query rows | DML | DML rows | Wall ms | Change              |
| ------- | ------ | ---- | ---- | ---------- | --- | -------- | ------- | ------------------- |
| 1       | 22     | 455  | 0    | 0          | 1   | 1        | 94      | First published run |
| 200     | 411    | 5231 | 0    | 0          | 1   | 200      | 606     | First published run |
| 2000    |        |      |      |            |     |          |         | Not published yet   |

The version measured here has a defect that skips every record after the first
200, so a 2,000-record number would only be the cost of 200. A fix is on its way,
and this row is filled in once it is merged.

Consumer lines: 15 (with the platform) / 21 (plain Apex)

## Data builder and seeder

_Run: 2026-10-13, e2a5cf0, API 66.0_

| Records | CPU ms | Heap   | SOQL | Query rows | DML | DML rows | Wall ms | Change              |
| ------- | ------ | ------ | ---- | ---------- | --- | -------- | ------- | ------------------- |
| 1       | 68     | 3756   | 0    | 0          | 2   | 2        | 223     | First published run |
| 200     | 434    | 28127  | 0    | 0          | 2   | 201      | 780     | First published run |
| 2000    | 4773   | 250528 | 0    | 0          | 2   | 2001     | 9060    | First published run |

Consumer lines: 13 (with the platform) / 31 (plain Apex)
