/**
 * This file is part of the Forge Platform project
 *
 * Virtual base class for all trigger handlers.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public virtual with sharing class ForgeTriggerHandler {

    private static final Map<String, Integer> runCounts = new Map<String, Integer>();
    private static final Set<String> bypassedHandlers = new Set<String>();
    private static final Map<String, Integer> activeDepths = new Map<String, Integer>();

    public virtual Integer getMaxReEntries() { return 1; }

    public static void bypass(String handlerName)
    {
        bypassedHandlers.add(handlerName);
    }

    public static void clearBypass(String handlerName)
    {
        bypassedHandlers.remove(handlerName);
    }

    public static void clearAllBypasses()
    {
        bypassedHandlers.clear();
    }

    public static Boolean isBypassed(String handlerName)
    {
        return bypassedHandlers.contains(handlerName);
    }

    public static Integer getRunCount(String handlerName)
    {
        return runCounts.get(handlerName) == null ? 0 : runCounts.get(handlerName);
    }

    public static void resetRunCounts()
    {
        runCounts.clear();
    }

    public void handle()
    {
        String handlerName = String.valueOf(this).split(':')[0];
        Integer depth = getActiveDepth(handlerName);

        if (isBypassed(handlerName)) { return; }
        if (depth >= getMaxReEntries()) { return; }

        runCounts.put(handlerName, getRunCount(handlerName) + 1);
        activeDepths.put(handlerName, depth + 1);

        ForgeTriggerContext ctx = new ForgeTriggerContext(
            Trigger.operationType, Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap
        );

        try
        {
            onTrigger(ctx);
        }
        finally
        {
            activeDepths.put(handlerName, depth);
        }
    }

    private static Integer getActiveDepth(String handlerName)
    {
        return activeDepths.get(handlerName) == null ? 0 : activeDepths.get(handlerName);
    }

    protected virtual void onTrigger(ForgeTriggerContext ctx) {}
}