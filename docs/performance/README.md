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
- Each benchmark run uses one fresh scratch org, and each version is measured in it
  five times. The table shows the middle (median) value, so one slow run doesn't
  skew it.
- CPU time differs between scratch orgs: the same data builder code at 200 records
  measured 14% slower in a new org than in the one before. So a change is never
  compared with numbers from another org. The previous published version is
  deployed to the same org and measured first, then the change is deployed and
  measured, and the Change column compares the two. The results file keeps the
  previous version's numbers from that org under `same_org_baseline`.
- A size that was published before is published again only if it was compared.
  If the previous version's run in the same org did not measure that size, or did
  not handle every record of it, the change's numbers are not published, and both
  versions are measured again.
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
  712 ms, so a smaller threshold would flag unchanged code.
- **10% queries, query rows, DML statements or DML rows.** These are exact counts:
  the same code gives the same number every time.
- **10% heap, counting only changes of 512 bytes or more.** At 200 and 2,000
  records the same code's heap repeats within half a percent, so 10% catches real
  growth. At 1 record the readings are small (about 450 bytes for the trigger
  handler) and the same code has read up to 63 bytes apart between orgs, more than
  10% of it. The 512-byte floor keeps that noise from counting.

A regression must be fixed or explained before it is merged. The thresholds are
set in `perf/thresholds.json`. Wall time is shown but is not checked. Faster numbers
are reported too.

## Trigger handler framework

_Run: 2026-10-14, f44dffa, API 66.0_

| Records | CPU ms | Heap  | SOQL | Query rows | DML | DML rows | Wall ms | Change            |
| ------- | ------ | ----- | ---- | ---------- | --- | -------- | ------- | ----------------- |
| 1       | 20     | 487   | 0    | 0          | 1   | 1        | 91      | within thresholds |
| 200     | 376    | 5263  | 0    | 0          | 1   | 200      | 574     | within thresholds |
| 2000    | 3550   | 48463 | 0    | 0          | 1   | 2000     | 5003    | within thresholds |

Consumer lines: 15 (with the platform) / 21 (plain Apex)

## Data builder and seeder

_Run: 2026-10-14, f44dffa, API 66.0_

| Records | CPU ms | Heap   | SOQL | Query rows | DML | DML rows | Wall ms | Change            |
| ------- | ------ | ------ | ---- | ---------- | --- | -------- | ------- | ----------------- |
| 1       | 64     | 3926   | 0    | 0          | 2   | 2        | 183     | within thresholds |
| 200     | 505    | 28297  | 0    | 0          | 2   | 201      | 848     | within thresholds |
| 2000    | 4738   | 250646 | 0    | 0          | 2   | 2001     | 8492    | within thresholds |

Consumer lines: 13 (with the platform) / 31 (plain Apex)

## ForgeHttp

_Run: 2026-10-14, f44dffa, API 66.0_

The scenario: a sales user inserts Accounts, the Account trigger's handler sends
them to an ERP through ForgeHttp, and a mock answers for the ERP. The save queues
the sending as background jobs (queueables), which make the callouts, so the cost
is in two places: the save itself, and the jobs it queues.

This is the first published run of ForgeHttp, so every row reads "First published
run": there is no earlier version to compare it with. The next change to ForgeHttp
is compared with these numbers.

The save, measured like the other modules:

| Records | CPU ms | Heap  | SOQL | Query rows | DML | DML rows | Wall ms | Change              |
| ------- | ------ | ----- | ---- | ---------- | --- | -------- | ------- | ------------------- |
| 1       | 24     | 1059  | 0    | 0          | 1   | 1        | 160     | First published run |
| 200     | 317    | 5835  | 0    | 0          | 1   | 200      | 578     | First published run |
| 2000    | 3158   | 49035 | 0    | 0          | 1   | 2000     | 5070    | First published run |

The jobs the save queues. Each job runs in its own transaction, with its own
limits. The job columns are read when the job saves the Accounts it sent, in the
Account trigger that save fires, and show the most any one job had used by then.
They leave out what a job does after that save: its after-calls step, with the
savepoint that step opens even when it has nothing to do (one more DML statement),
queueing the next job when there are more records to send, and saving any
integration failures. A job's real totals are higher than these columns, and the
check below covers each job only up to its save.

| Records | Callouts in save | Jobs queued | Jobs run | Callouts per job | Job CPU ms | Job SOQL | Job query rows | Job DML | Job DML rows | Failures |
| ------- | ---------------- | ----------- | -------- | ---------------- | ---------- | -------- | -------------- | ------- | ------------ | -------- |
| 1       | 0                | 1           | 1        | 1                | 34         | 1        | 1              | 1       | 1            | 0        |
| 200     | 0                | 1           | 1        | 4                | 478        | 1        | 200            | 1       | 200          | 0        |
| 2000    | 0                | 10          | 10       | 4                | 546        | 1        | 200            | 1       | 200          | 0        |

| Column                   | What it means                                                                              |
| ------------------------ | ------------------------------------------------------------------------------------------ |
| Callouts in save         | Callouts made in the save's own transaction. A trigger cannot call out, so it should be 0. |
| Jobs queued, Jobs run    | Background jobs the save queued, and how many of them ran.                                 |
| Callouts per job         | The most callouts one job made. The limit is 100.                                          |
| Job CPU ms               | The most CPU time one job used. The limit for a background job is 60,000.                  |
| Job SOQL, Job query rows | The most queries and query rows one job used.                                              |
| Job DML, Job DML rows    | The most DML statements and DML rows one job used.                                         |
| Failures                 | Integration failures the jobs logged (`Integration_Failure__c` records).                   |

Every job column but Jobs run and Failures is checked against the thresholds like
the save's, up to each job's save: callouts in the save, jobs queued, and each
job's callouts, CPU time, queries, query rows, DML statements and DML rows. The
field-query table below is published but not checked.

A job's heap is not shown or checked: the only place the benchmark can read it is
the Account trigger the job's own update fires, and a reading there leaves out
what the job holds around that update. A test that read heap both in the job and in
that trigger found about 91 KB in the job and 13 KB in the trigger. The trigger
reading is kept in the results file as `job_trigger_heap_bytes`, under a name that
says where it was taken. Each run in the results file also keeps every job's own
reading under `job_readings`. The test context runs the jobs one after another in
one transaction, so their CPU readings add up. Job CPU ms is each reading less the
one before, and `job_readings` lets anyone check that.

Each job reads the Accounts it sends back with a query of every readable Account
field. This table shows what that query costs against one of only the fields the
job uses. Each job reads at most 200 records, so when 2,000 are saved one job
still reads 200, and that row is a second sample at 200 records read.

| Records saved | Records read by one job | Readable fields | Every-field query CPU ms | Every-field query heap | Only-used-fields query CPU ms | Only-used-fields query heap |
| ------------- | ----------------------- | --------------- | ------------------------ | ---------------------- | ----------------------------- | --------------------------- |
| 1             | 1                       | 58              | 11                       | 400                    | 4                             | 91                          |
| 200           | 200                     | 58              | 23                       | 76474                  | 6                             | 16266                       |
| 2000          | 200                     | 58              | 23                       | 66874                  | 7                             | 16266                       |

Consumer lines: 89 (with the platform) / 210 (plain Apex)
