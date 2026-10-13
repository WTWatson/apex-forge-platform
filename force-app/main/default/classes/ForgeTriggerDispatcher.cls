/**
 * This file is part of the Forge Platform project
 *
 * Static dispatcher invoked from trigger files.
 * Accepts an ordered list of handler instances and runs them in sequence.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeTriggerDispatcher {

    /** Runs one handler for the current trigger event; call it from the trigger. */
    public static void run(ForgeTriggerHandler handler)
    {
        handler.handle();
    }

    /** Runs the given handlers for the current trigger event, in the order listed. */
    public static void run(List<ForgeTriggerHandler> handlers)
    {
        for (ForgeTriggerHandler handler : handlers)
        {
            handler.handle();
        }
    }
}
