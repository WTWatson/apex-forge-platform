/**
 * This file is part of the Forge Platform project
 *
 * Immutable snapshot of the current trigger context.
 * Passed to handler onTrigger() so handlers never reference Trigger.* directly.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeTriggerContext {

    public final System.TriggerOperation operationType;
    public final List<SObject> newRecords;
    public final List<SObject> oldRecords;
    public final Map<Id, SObject> newMap;
    public final Map<Id, SObject> oldMap;

    public ForgeTriggerContext(System.TriggerOperation operationType,
                               List<SObject> newRecords, Map<Id, SObject> newMap,
                               List<SObject> oldRecords, Map<Id, SObject> oldMap) {
        this.operationType = operationType;
        this.newRecords = newRecords;
        this.newMap = newMap;
        this.oldRecords = oldRecords;
        this.oldMap = oldMap;
    }

    public static ForgeTriggerContext forInsert(List<SObject> newRecords)
    {
        return new ForgeTriggerContext(
            System.TriggerOperation.BEFORE_INSERT, newRecords, null, null, null
        );
    }

    public static ForgeTriggerContext forUpdate(List<SObject> newRecords, List<SObject> oldRecords)
    {
        Map<Id, SObject> oldMap = new Map<Id, SObject>(oldRecords);
        Map<Id, SObject> newMap = new Map<Id, SObject>(newRecords);
        return new ForgeTriggerContext(
            System.TriggerOperation.BEFORE_UPDATE, newRecords, newMap, oldRecords, oldMap
        );
    }

    public static ForgeTriggerContext forDelete(List<SObject> oldRecords)
    {
        Map<Id, SObject> oldMap = new Map<Id, SObject>(oldRecords);
        return new ForgeTriggerContext(
            System.TriggerOperation.BEFORE_DELETE, null, null, oldRecords, oldMap
        );
    }

    public static ForgeTriggerContext forUndelete(List<SObject> newRecords)
    {
        Map<Id, SObject> newMap = new Map<Id, SObject>(newRecords);
        return new ForgeTriggerContext(
            System.TriggerOperation.AFTER_UNDELETE, newRecords, newMap, null, null
        );
    }

    public Boolean hasChanged(SObject record, SObjectField field)
    {
        if (oldMap == null) { return true; }

        SObject oldRecord = oldMap.get(record.Id);
        if (oldRecord == null) { return true; }

        return record.get(field) != oldRecord.get(field);
    }
}