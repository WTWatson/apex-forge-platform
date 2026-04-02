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

    public static void run(ForgeTriggerHandler handler)
    {
        handler.handle();
    }

    public static void run(List<ForgeTriggerHandler> handlers)
    {
        for (ForgeTriggerHandler handler : handlers)
        {
            handler.handle();
        }
    }
}
