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

1.
2.
3.
