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

    /** Which trigger event is running, such as before insert or after update. */
    public final System.TriggerOperation operationType;
    /** The records as they are being saved; null on delete. */
    public final List<SObject> newRecords;
    /** The records as they were before the change; null on insert and undelete. */
    public final List<SObject> oldRecords;
    /** The records being saved, by Id; null before insert and on delete. */
    public final Map<Id, SObject> newMap;
    /** The records as they were before the change, by Id; null on insert and undelete. */
    public final Map<Id, SObject> oldMap;

    /** Captures one trigger event's records so a handler can read them without touching Trigger directly. */
    public ForgeTriggerContext(System.TriggerOperation operationType,
                               List<SObject> newRecords, Map<Id, SObject> newMap,
                               List<SObject> oldRecords, Map<Id, SObject> oldMap) {
        this.operationType = operationType;
        this.newRecords = newRecords;
        this.newMap = newMap;
        this.oldRecords = oldRecords;
        this.oldMap = oldMap;
    }

    /** Builds a before-insert event for the given records, so a handler can be exercised without DML. */
    public static ForgeTriggerContext forInsert(List<SObject> newRecords)
    {
        return new ForgeTriggerContext(
            System.TriggerOperation.BEFORE_INSERT, newRecords, null, null, null
        );
    }

    /** Builds a before-update event from the changed and the original records, so a handler can be exercised without DML. */
    public static ForgeTriggerContext forUpdate(List<SObject> newRecords, List<SObject> oldRecords)
    {
        Map<Id, SObject> oldMap = new Map<Id, SObject>(oldRecords);
        Map<Id, SObject> newMap = new Map<Id, SObject>(newRecords);
        return new ForgeTriggerContext(
            System.TriggerOperation.BEFORE_UPDATE, newRecords, newMap, oldRecords, oldMap
        );
    }

    /** Builds a before-delete event for the given records, so a handler can be exercised without DML. */
    public static ForgeTriggerContext forDelete(List<SObject> oldRecords)
    {
        Map<Id, SObject> oldMap = new Map<Id, SObject>(oldRecords);
        return new ForgeTriggerContext(
            System.TriggerOperation.BEFORE_DELETE, null, null, oldRecords, oldMap
        );
    }

    /** Builds an after-undelete event for the given records, so a handler can be exercised without DML. */
    public static ForgeTriggerContext forUndelete(List<SObject> newRecords)
    {
        Map<Id, SObject> newMap = new Map<Id, SObject>(newRecords);
        return new ForgeTriggerContext(
            System.TriggerOperation.AFTER_UNDELETE, newRecords, newMap, null, null
        );
    }

    /** Tells whether the field's value differs from the record's earlier version; true when there is no earlier version, as on insert. */
    public Boolean hasChanged(SObject record, SObjectField field)
    {
        if (oldMap == null) { return true; }

        SObject oldRecord = oldMap.get(record.Id);
        if (oldRecord == null) { return true; }

        return record.get(field) != oldRecord.get(field);
    }
}