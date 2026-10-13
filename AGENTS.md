# Apex Forge Platform: agent guidance

Business logic is what the developer writes. No boilerplate, no helper functions:
the platform handles the rest. Every module is measured, and its numbers ship with
it in `docs/performance/`.

Salesforce DX project. Source lives in force-app/main/default.

## Apex standards
- Bulkify everything: handlers must work for 200+ records per transaction.
- No SOQL or DML inside loops. Collect IDs, query once, use maps.
- Classes declare sharing explicitly (`with sharing` unless there is a documented reason).
- Enforce CRUD/FLS on user-facing data access (e.g. `WITH USER_MODE` / `AccessLevel.USER_MODE`).
- Triggers contain no logic: one trigger per object, delegating to the Forge Trigger Handler.
- Respect the handler's ordered execution, recursion guard, and bypass API; do not work around them.
- Every public type and method says in one sentence what it is for. Names say what a
  thing does in business language; no `Util` or `Helper` grab-bags.

## Tests
- Every Apex change includes tests with real assertions, not coverage padding.
- Test bulk (200 records), single-record, and negative paths; use Test.startTest/stopTest.
- No SeeAllData=true. Build test data in the test or a factory class.

## Verification
- Apex tests run in the seat's own scratch org, from the Dev Hub `forge-devhub`:
  `sf apex run test -o forge-<seat>-<n> --test-level RunLocalTests --code-coverage --wait 20`.
  A change is not done until that run passes, and the run's numbers go in the handoff.
- Run `npm run lint` and `npm run prettier:verify`; format only the files you changed.
- One module or one fix per branch (`feat/`, `fix/`, `perf/` or `docs/`), pushed to
  that branch only, as one pull request into `main`. Never push to `main`, never
  merge, never force-push: Will merges.
