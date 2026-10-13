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

    /** How many runs of this handler may be nested inside each other; override it to allow re-entry. */
    public virtual Integer getMaxReEntries() { return 1; }

    /** Switches off the handler with this class name for the rest of the transaction, until its bypass is cleared. */
    public static void bypass(String handlerName)
    {
        bypassedHandlers.add(handlerName);
    }

    /** Switches the handler with this class name back on after a bypass. */
    public static void clearBypass(String handlerName)
    {
        bypassedHandlers.remove(handlerName);
    }

    /** Switches every bypassed handler back on. */
    public static void clearAllBypasses()
    {
        bypassedHandlers.clear();
    }

    /** Tells whether the handler with this class name is switched off. */
    public static Boolean isBypassed(String handlerName)
    {
        return bypassedHandlers.contains(handlerName);
    }

    /** Tells how many times the handler with this class name has run in this transaction. */
    public static Integer getRunCount(String handlerName)
    {
        return runCounts.get(handlerName) == null ? 0 : runCounts.get(handlerName);
    }

    /** Forgets every handler's run count, for example between steps of a test. */
    public static void resetRunCounts()
    {
        runCounts.clear();
    }

    /** Runs this handler for the current trigger event, unless it is switched off or is already running inside itself as deeply as its limit allows. */
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

    /** Holds this handler's business logic for the trigger event; override it in each handler. */
    protected virtual void onTrigger(ForgeTriggerContext ctx) {}
}