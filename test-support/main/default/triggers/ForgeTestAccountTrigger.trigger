/**
 * This file is part of the Forge Platform project
 *
 * Test support only: runs the handlers a test registered in ForgeTestAccountHandlers,
 * so an integration is tested as it is started in an org, from an Account trigger.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
trigger ForgeTestAccountTrigger on Account (after insert, after update) {
    if (Test.isRunningTest()) { ForgeTriggerDispatcher.run(ForgeTestAccountHandlers.toRun); }
}
