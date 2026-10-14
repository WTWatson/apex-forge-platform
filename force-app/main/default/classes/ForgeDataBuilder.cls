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
        return fieldsOf(objectType).get(String.valueOf(field)) == field;
    }

    private static final Map<SObjectType, Map<String, SObjectField>> FIELDS_BY_OBJECT =
        new Map<SObjectType, Map<String, SObjectField>>();

    // Keyed by object and running user, because System.runAs can change which fields are createable.
    private static final Map<String, List<Schema.DescribeFieldResult>> REQUIRED_FIELDS_BY_OBJECT =
        new Map<String, List<Schema.DescribeFieldResult>>();

    private static Map<String, SObjectField> fieldsOf(SObjectType objectType)
    {
        if (!FIELDS_BY_OBJECT.containsKey(objectType)) {
            FIELDS_BY_OBJECT.put(objectType,
                objectType.getDescribe(SObjectDescribeOptions.DEFERRED).fields.getMap());
        }
        return FIELDS_BY_OBJECT.get(objectType);
    }

    private static List<Schema.DescribeFieldResult> requiredFieldsOf(SObjectType objectType)
    {
        String key = String.valueOf(objectType) + ':' + UserInfo.getUserId();
        if (!REQUIRED_FIELDS_BY_OBJECT.containsKey(key)) {
            List<Schema.DescribeFieldResult> required = new List<Schema.DescribeFieldResult>();
            for (SObjectField field : fieldsOf(objectType).values()) {
                Schema.DescribeFieldResult describe = field.getDescribe();
                if (!describe.isCreateable()) { continue; }
                if (describe.isNillable()) { continue; }
                if (describe.isDefaultedOnCreate()) { continue; }
                if (describe.getType() == Schema.DisplayType.REFERENCE) { continue; }
                required.add(describe);
            }
            REQUIRED_FIELDS_BY_OBJECT.put(key, required);
        }
        return REQUIRED_FIELDS_BY_OBJECT.get(key);
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
            List<Schema.DescribeFieldResult> toFill = autoFillOn
                ? requiredFieldsToFill() : new List<Schema.DescribeFieldResult>();
            Map<SObjectField, Object> sameForEveryRecord = valuesSameForEveryRecord(toFill);
            List<Schema.DescribeFieldResult> fieldsThatVary = fieldsThatVaryByRecord(toFill);
            for (Integer index = 0; index < recordCount; index++) {
                SObject record = objectType.newSObject();
                for (SObjectField field : fieldValues.keySet()) {
                    Object value = fieldValues.get(field);
                    if (value instanceof ValueProvider) {
                        value = ((ValueProvider) value).get(index);
                    }
                    record.put(field, value);
                }
                for (SObjectField field : sameForEveryRecord.keySet()) {
                    record.put(field, sameForEveryRecord.get(field));
                }
                for (Schema.DescribeFieldResult describe : fieldsThatVary) {
                    record.put(describe.getSObjectField(),
                        placeholderFor(describe, describe.getType(), index));
                }
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

        private List<Schema.DescribeFieldResult> requiredFieldsToFill()
        {
            List<Schema.DescribeFieldResult> toFill = new List<Schema.DescribeFieldResult>();
            for (Schema.DescribeFieldResult describe : requiredFieldsOf(objectType)) {
                if (!fieldValues.containsKey(describe.getSObjectField())) { toFill.add(describe); }
            }
            return toFill;
        }

        private Map<SObjectField, Object> valuesSameForEveryRecord(
            List<Schema.DescribeFieldResult> toFill)
        {
            Map<SObjectField, Object> values = new Map<SObjectField, Object>();
            for (Schema.DescribeFieldResult describe : toFill) {
                if (variesByRecord(describe.getType())) { continue; }
                Object placeholder = placeholderFor(describe, describe.getType(), 0);
                if (placeholder != null) { values.put(describe.getSObjectField(), placeholder); }
            }
            return values;
        }

        private List<Schema.DescribeFieldResult> fieldsThatVaryByRecord(
            List<Schema.DescribeFieldResult> toFill)
        {
            List<Schema.DescribeFieldResult> varying = new List<Schema.DescribeFieldResult>();
            for (Schema.DescribeFieldResult describe : toFill) {
                if (variesByRecord(describe.getType())) { varying.add(describe); }
            }
            return varying;
        }

        private Boolean variesByRecord(Schema.DisplayType fieldType)
        {
            if (fieldType == Schema.DisplayType.EMAIL || fieldType == Schema.DisplayType.PHONE) { return true; }
            Boolean isText = fieldType == Schema.DisplayType.STRING || fieldType == Schema.DisplayType.TEXTAREA;
            return isText && recordCount > 1;
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
