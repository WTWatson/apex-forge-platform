/**
 * This file is part of the Forge Platform project
 *
 * Test support only: the handlers that the ForgeTestAccountTrigger on Account runs.
 * A test sets them; everywhere else the list stays empty and the trigger does nothing.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeTestAccountHandlers {

    /** The handlers a test wants the Account test trigger to run, in order. */
    public static List<ForgeTriggerHandler> toRun = new List<ForgeTriggerHandler>();
}
