# Apex Forge Platform: roadmap

Business logic is what the developer writes; the platform handles the rest. Each
module ships as one pull request with its tests, its consumer sample
(`perf/scenarios/<module>/`) and its numbers in `docs/performance/`.

## Shipped

- **Trigger handler framework**: `ForgeTriggerHandler`, `ForgeTriggerDispatcher`,
  `ForgeTriggerContext`. Ordered execution, a recursion guard and a bypass API; one
  trigger per object, no logic in the trigger.
- **Data builder and seeder**: `ForgeDataBuilder`, `ForgeDataSeeder`. Test and
  sample data without boilerplate.
- **ForgeHttp**: `ForgeHttp`, `ForgeIntegration`, `ForgeHttpMock`. Integration
  callouts without the plumbing. A developer names the Named Credential and writes
  what the reply changes; the platform builds the request, moves the callout out of
  the trigger, splits records into calls, retries and mocks it in tests. Design:
  `docs/design/forge-http.md`.

## Next, in order

_The maintainer sets this order. Each module gets a short design note in
`docs/design/<module>.md` before any code is written._

1. **User access checks**: reading and saving records with the running user's
   object and field permissions, without boilerplate. A developer names the records
   and fields; the platform checks access, runs the query and the DML in user mode
   and raises one error naming the object and field that failed. Design:
   `docs/design/user-access.md`.
2.
3.
