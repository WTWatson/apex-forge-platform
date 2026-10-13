/**
 * This file is part of the Forge Platform project
 *
 * Generic fluent test data builder. Works with any SObjectType — no per-object
 * subclass required. Auto-fills required fields from Schema describes, supports
 * .count(recordCount) for bulk construction, and accepts ForgeDataBuilder.ValueProvider
 * for per-record variation.
 *
 * Fluent API:
 *   ForgeDataBuilder.of(SObjectType)
 *     .with(field, value)                 // literal value or ValueProvider
 *     .parent(lookupField, savedRecord)   // wire a REFERENCE lookup from a saved parent
 *     .count(recordCount)                 // build that many records (default 1)
 *     .autoFill(false)                    // disable required-field auto-fill
 *     .build()    | .buildList()          // construct without DML
 *     .persist()  | .persistList()        // construct and insert
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeDataBuilder {

    /** Raised when a builder is set up wrongly, such as with a field of another object or an unsaved parent. */
    public class ConfigException extends Exception {}

    /** Supplies the value for the record at the given zero-based index, through get(index), when several are built at once. */
    public interface ValueProvider { Object get(Integer index); }

    /** Starts building test records of the given object type. */
    public static Builder of(SObjectType objectType) { return new Builder(objectType); }

    /** Tells whether the field is a field of the given object type. */
    public static Boolean fieldBelongsTo(SObjectType objectType, SObjectField field)
    {
        return objectType.getDescribe().fields.getMap().values().contains(field);
    }

    /** Collects the field values and the record count for one set of test records, then builds or inserts them. */
    public class Builder {
        private final SObjectType objectType;
        private final Map<SObjectField, Object> fieldValues = new Map<SObjectField, Object>();
        private Integer recordCount = 1;
        private Boolean autoFillOn = true;

        /** Starts a builder for the given object type; ForgeDataBuilder.of reads better in a test. */
        public Builder(SObjectType objectType)
        {
            if (objectType == null) { throw new ConfigException('SObjectType required'); }
            this.objectType = objectType;
        }

        /** Sets a field on every record, to one value or to a ValueProvider that supplies each record's value by its index. */
        public Builder with(SObjectField field, Object value)
        {
            if (field == null) { throw new ConfigException('field required'); }
            if (!fieldBelongsTo(objectType, field)) {
                throw new ConfigException('field ' + field + ' does not belong to ' + objectType);
            }
            fieldValues.put(field, value);
            return this;
        }

        /** Links every record to an already-saved parent record through the given lookup field. */
        public Builder parent(SObjectField lookupField, SObject parentRecord)
        {
            if (lookupField == null) { throw new ConfigException('lookup field required'); }
            Schema.DescribeFieldResult lookupDescribe = lookupField.getDescribe();
            if (lookupDescribe.getType() != Schema.DisplayType.REFERENCE) {
                throw new ConfigException(
                    'parent() requires a REFERENCE field, got ' + lookupDescribe.getType());
            }
            if (parentRecord == null || parentRecord.Id == null) {
                throw new ConfigException('parent must be saved before linking (Id is null)');
            }
            Schema.SObjectType parentType = parentRecord.getSObjectType();
            if (!lookupDescribe.getReferenceTo().contains(parentType)) {
                throw new ConfigException(
                    'parent SObjectType ' + parentType + ' is not a valid reference for ' + lookupField);
            }
            return with(lookupField, parentRecord.Id);
        }

        /** Sets how many records to build; the default is one. */
        public Builder count(Integer recordCount)
        {
            if (recordCount == null || recordCount < 1) { throw new ConfigException('count must be >= 1'); }
            this.recordCount = recordCount;
            return this;
        }

        /** Turns on or off the filling of required fields with placeholder values; it is on by default. */
        public Builder autoFill(Boolean enabled) { this.autoFillOn = enabled; return this; }

        /** Returns the one record without inserting it; use buildList when building more than one. */
        public SObject build()
        {
            if (recordCount > 1) {
                throw new ConfigException('count > 1 — use buildList()');
            }
            return buildList()[0];
        }

        /** Returns all the records without inserting them. */
        public List<SObject> buildList()
        {
            List<SObject> records = new List<SObject>();
            Map<SObjectField, Schema.DescribeFieldResult> describesByField =
                autoFillOn ? fieldDescribes() : null;
            for (Integer index = 0; index < recordCount; index++) {
                SObject record = objectType.newSObject();
                for (SObjectField field : fieldValues.keySet()) {
                    Object value = fieldValues.get(field);
                    if (value instanceof ValueProvider) {
                        value = ((ValueProvider) value).get(index);
                    }
                    record.put(field, value);
                }
                if (autoFillOn) { applyAutoFill(record, describesByField, index); }
                records.add(record);
            }
            return records;
        }

        /** Inserts the one record and returns it; use persistList when building more than one. */
        public SObject persist()
        {
            if (recordCount > 1) {
                throw new ConfigException('count > 1 — use persistList()');
            }
            SObject record = buildList()[0];
            insert record;
            return record;
        }

        /** Inserts all the records and returns them. */
        public List<SObject> persistList()
        {
            List<SObject> records = buildList();
            insert records;
            return records;
        }

        private Map<SObjectField, Schema.DescribeFieldResult> fieldDescribes()
        {
            Map<SObjectField, Schema.DescribeFieldResult> describesByField
                = new Map<SObjectField, Schema.DescribeFieldResult>();
            for (SObjectField field : objectType.getDescribe().fields.getMap().values()) {
                describesByField.put(field, field.getDescribe());
            }
            return describesByField;
        }

        private void applyAutoFill(SObject record,
            Map<SObjectField, Schema.DescribeFieldResult> describesByField, Integer index)
        {
            for (SObjectField field : describesByField.keySet()) {
                if (fieldValues.containsKey(field)) { continue; }
                Schema.DescribeFieldResult describe = describesByField.get(field);
                if (!describe.isCreateable()) { continue; }
                if (describe.isNillable()) { continue; }
                if (describe.isDefaultedOnCreate()) { continue; }
                Schema.DisplayType fieldType = describe.getType();
                if (fieldType == Schema.DisplayType.REFERENCE) { continue; }
                Object placeholder = placeholderFor(describe, fieldType, index);
                if (placeholder != null) { record.put(field, placeholder); }
            }
        }

        private Object placeholderFor(Schema.DescribeFieldResult describe,
            Schema.DisplayType fieldType, Integer index)
        {
            if (fieldType == Schema.DisplayType.STRING || fieldType == Schema.DisplayType.TEXTAREA) {
                String text = recordCount > 1 ? (describe.getName() + ' ' + (index + 1)) : 'Test';
                Integer maxLength = describe.getLength();
                return (maxLength > 0 && text.length() > maxLength) ? text.substring(0, maxLength) : text;
            }
            if (fieldType == Schema.DisplayType.EMAIL) { return ForgeDataSeeder.email(); }
            if (fieldType == Schema.DisplayType.PHONE) { return ForgeDataSeeder.phone(); }
            if (fieldType == Schema.DisplayType.URL) { return 'https://example.com'; }
            if (fieldType == Schema.DisplayType.INTEGER || fieldType == Schema.DisplayType.LONG) { return 0; }
            if (fieldType == Schema.DisplayType.DOUBLE || fieldType == Schema.DisplayType.CURRENCY
                || fieldType == Schema.DisplayType.PERCENT) { return 0; }
            if (fieldType == Schema.DisplayType.DATE) { return Date.today(); }
            if (fieldType == Schema.DisplayType.DATETIME) { return Datetime.now(); }
            if (fieldType == Schema.DisplayType.TIME) { return Time.newInstance(0, 0, 0, 0); }
            if (fieldType == Schema.DisplayType.BOOLEAN) { return false; }
            if (fieldType == Schema.DisplayType.PICKLIST || fieldType == Schema.DisplayType.COMBOBOX) {
                for (Schema.PicklistEntry entry : describe.getPicklistValues()) {
                    if (entry.isActive()) { return entry.getValue(); }
                }
            }
            return null;
        }
    }
}
