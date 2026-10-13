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

    /** How many times this handler may run in one transaction; override it to allow re-entry. */
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

    /** Forgets every handler's run count so each can run again, for example between steps of a test. */
    public static void resetRunCounts()
    {
        runCounts.clear();
    }

    /** Runs this handler for the current trigger event, unless it is switched off or has reached its re-entry limit. */
    public void handle()
    {
        String handlerName = String.valueOf(this).split(':')[0];
        Integer count = getRunCount(handlerName);

        if (isBypassed(handlerName)) { return; }
        if (count >= getMaxReEntries()) { return; }

        runCounts.put(handlerName, count + 1);

        ForgeTriggerContext ctx = new ForgeTriggerContext(
            Trigger.operationType, Trigger.new, Trigger.newMap, Trigger.old, Trigger.oldMap
        );

        onTrigger(ctx);
    }

    /** Holds this handler's business logic for the trigger event; override it in each handler. */
    protected virtual void onTrigger(ForgeTriggerContext ctx) {}
}