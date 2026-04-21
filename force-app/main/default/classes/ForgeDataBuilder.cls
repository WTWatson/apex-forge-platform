/**
 * This file is part of the Forge Platform project
 *
 * Generic fluent test data builder. Works with any SObjectType — no per-object
 * subclass required. Auto-fills required fields from Schema describes, supports
 * .count(n) for bulk construction, and accepts ForgeDataBuilder.ValueProvider for
 * per-record variation.
 *
 * Fluent API:
 *   ForgeDataBuilder.of(SObjectType)
 *     .with(field, value)             // literal value or ValueProvider
 *     .parent(fkField, savedRecord)   // wire a REFERENCE lookup from a saved parent
 *     .count(n)                       // build n records (default 1)
 *     .autoFill(false)                // disable required-field auto-fill
 *     .build()    | .buildList()      // construct without DML
 *     .persist()  | .persistList()    // construct and insert
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeDataBuilder {

    public class ConfigException extends Exception {}

    public interface ValueProvider { Object get(Integer index); }

    public static Builder of(SObjectType t) { return new Builder(t); }

    public static Boolean fieldBelongsTo(SObjectType t, SObjectField f)
    {
        return t.getDescribe().fields.getMap().values().contains(f);
    }

    public class Builder {
        private final SObjectType sObjType;
        private final Map<SObjectField, Object> fieldValues = new Map<SObjectField, Object>();
        private Integer howMany = 1;
        private Boolean autoFillOn = true;

        public Builder(SObjectType t)
        {
            if (t == null) { throw new ConfigException('SObjectType required'); }
            this.sObjType = t;
        }

        public Builder with(SObjectField f, Object value)
        {
            if (f == null) { throw new ConfigException('field required'); }
            if (!fieldBelongsTo(sObjType, f)) {
                throw new ConfigException('field ' + f + ' does not belong to ' + sObjType);
            }
            fieldValues.put(f, value);
            return this;
        }

        public Builder parent(SObjectField fk, SObject parentRecord)
        {
            if (fk == null) { throw new ConfigException('FK field required'); }
            Schema.DescribeFieldResult dfr = fk.getDescribe();
            if (dfr.getType() != Schema.DisplayType.REFERENCE) {
                throw new ConfigException(
                    'parent() requires a REFERENCE field, got ' + dfr.getType());
            }
            if (parentRecord == null || parentRecord.Id == null) {
                throw new ConfigException('parent must be saved before linking (Id is null)');
            }
            Schema.SObjectType parentType = parentRecord.getSObjectType();
            if (!dfr.getReferenceTo().contains(parentType)) {
                throw new ConfigException(
                    'parent SObjectType ' + parentType + ' is not a valid reference for ' + fk);
            }
            return with(fk, parentRecord.Id);
        }

        public Builder count(Integer n)
        {
            if (n == null || n < 1) { throw new ConfigException('count must be >= 1'); }
            this.howMany = n;
            return this;
        }

        public Builder autoFill(Boolean enabled) { this.autoFillOn = enabled; return this; }

        public SObject build()
        {
            if (howMany > 1) {
                throw new ConfigException('count > 1 — use buildList()');
            }
            return buildList()[0];
        }

        public List<SObject> buildList()
        {
            List<SObject> out = new List<SObject>();
            Map<SObjectField, Schema.DescribeFieldResult> describes =
                autoFillOn ? fieldDescribes() : null;
            for (Integer i = 0; i < howMany; i++) {
                SObject rec = sObjType.newSObject();
                for (SObjectField f : fieldValues.keySet()) {
                    Object v = fieldValues.get(f);
                    if (v instanceof ValueProvider) {
                        v = ((ValueProvider) v).get(i);
                    }
                    rec.put(f, v);
                }
                if (autoFillOn) { applyAutoFill(rec, describes, i); }
                out.add(rec);
            }
            return out;
        }

        public SObject persist()
        {
            if (howMany > 1) {
                throw new ConfigException('count > 1 — use persistList()');
            }
            SObject rec = buildList()[0];
            insert rec;
            return rec;
        }

        public List<SObject> persistList()
        {
            List<SObject> recs = buildList();
            insert recs;
            return recs;
        }

        private Map<SObjectField, Schema.DescribeFieldResult> fieldDescribes()
        {
            Map<SObjectField, Schema.DescribeFieldResult> m
                = new Map<SObjectField, Schema.DescribeFieldResult>();
            for (SObjectField f : sObjType.getDescribe().fields.getMap().values()) {
                m.put(f, f.getDescribe());
            }
            return m;
        }

        private void applyAutoFill(SObject rec,
            Map<SObjectField, Schema.DescribeFieldResult> describes, Integer index)
        {
            for (SObjectField f : describes.keySet()) {
                if (fieldValues.containsKey(f)) { continue; }
                Schema.DescribeFieldResult dfr = describes.get(f);
                if (!dfr.isCreateable()) { continue; }
                if (dfr.isNillable()) { continue; }
                if (dfr.isDefaultedOnCreate()) { continue; }
                Schema.DisplayType t = dfr.getType();
                if (t == Schema.DisplayType.REFERENCE) { continue; }
                Object v = defaultFor(dfr, t, index);
                if (v != null) { rec.put(f, v); }
            }
        }

        private Object defaultFor(Schema.DescribeFieldResult dfr,
            Schema.DisplayType t, Integer index)
        {
            if (t == Schema.DisplayType.STRING || t == Schema.DisplayType.TEXTAREA) {
                String s = howMany > 1 ? (dfr.getName() + ' ' + (index + 1)) : 'Test';
                Integer max = dfr.getLength();
                return (max > 0 && s.length() > max) ? s.substring(0, max) : s;
            }
            if (t == Schema.DisplayType.EMAIL) { return ForgeDataSeeder.email(); }
            if (t == Schema.DisplayType.PHONE) { return ForgeDataSeeder.phone(); }
            if (t == Schema.DisplayType.URL) { return 'https://example.com'; }
            if (t == Schema.DisplayType.INTEGER || t == Schema.DisplayType.LONG) { return 0; }
            if (t == Schema.DisplayType.DOUBLE || t == Schema.DisplayType.CURRENCY
                || t == Schema.DisplayType.PERCENT) { return 0; }
            if (t == Schema.DisplayType.DATE) { return Date.today(); }
            if (t == Schema.DisplayType.DATETIME) { return Datetime.now(); }
            if (t == Schema.DisplayType.TIME) { return Time.newInstance(0, 0, 0, 0); }
            if (t == Schema.DisplayType.BOOLEAN) { return false; }
            if (t == Schema.DisplayType.PICKLIST || t == Schema.DisplayType.COMBOBOX) {
                for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
                    if (pe.isActive()) { return pe.getValue(); }
                }
            }
            return null;
        }
    }
}
