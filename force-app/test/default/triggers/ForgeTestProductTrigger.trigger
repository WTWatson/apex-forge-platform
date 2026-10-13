/**
 * This file is part of the Forge Platform project
 *
 * Test support only: runs the handlers a test registered in ForgeTestProductHandlers,
 * so the trigger handler is tested through a real trigger on an object every org has.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
trigger ForgeTestProductTrigger on Product2 (before insert, after insert, before update, after update) {
    if (Test.isRunningTest()) { ForgeTriggerDispatcher.run(ForgeTestProductHandlers.active); }
}
