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

## Next, in order

_The maintainer sets this order. Each module gets a short design note in
`docs/design/<module>.md` before any code is written._

1. **ForgeHttp**: integration callouts without the plumbing. A developer names the
   Named Credential and writes what the reply changes; the platform builds the
   request, moves the callout out of the trigger, splits records into calls,
   retries and mocks it in tests. Design: `docs/design/forge-http.md`.
2.
3.
