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
_Will fills this in through the inbox. The lead takes the first entry as the next
module and writes its design note in `docs/design/<module>.md` before any code._

1.
2.
3.
