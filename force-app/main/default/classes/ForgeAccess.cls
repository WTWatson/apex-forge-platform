/**
 * This file is part of the Forge Platform project
 *
 * Reads and saves records with the running user's permissions: every query and
 * every save runs in user mode, the object and field checks are made before any
 * DML, and a missing permission is raised as one error naming the object and field.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeAccess {

    private static final Set<String> AUDIT_FIELDS = new Set<String>{
        'id', 'createddate', 'createdbyid', 'lastmodifieddate', 'lastmodifiedbyid', 'systemmodstamp'
    };
    private static final Pattern UNSUPPORTED_OBJECT = Pattern.compile('sObject type \'(\\w+)\' is not supported');

    private static Map<Id, SObject> remembered = new Map<Id, SObject>();
    private static Map<SObjectType, Map<String, SObjectField>> fieldsByType = new Map<SObjectType, Map<String, SObjectField>>();
    private static Map<String, Boolean> maintainedBySalesforce = new Map<String, Boolean>();
    private static Set<String> leftOut = new Set<String>();

    /** The kinds of access a user may be missing. */
    public enum Access { READ, CREATE, EDIT, REMOVE }

    /** Runs the query with these binds as the user, and raises AccessDeniedException when the user may not read an object or field in it. */
    public static List<SObject> query(String soql, Map<String, Object> binds)
    {
        List<SObject> records;
        try
        {
            records = Database.queryWithBinds(soql, binds, AccessLevel.USER_MODE);
        }
        catch (QueryException failure)
        {
            throw accessDeniedOr(failure);
        }
        for (SObject record : records)
        {
            remembered.put(record.Id, record.clone(true, false, true, true));
        }
        return records;
    }

    /** Inserts the records with no Id and updates the rest, all or nothing, refusing the save when the user may not write a field it holds. */
    public static void save(List<SObject> records)
    {
        saveWritable(records, false);
    }

    /** A save that leaves out the fields the user may not edit, instead of refusing it. */
    public static LeavingOutUneditable leavingOutUneditable()
    {
        return new LeavingOutUneditable();
    }

    /** The fields, as Object.Field, that the last save left out because the user may not edit them. */
    public static Set<String> lastLeftOut()
    {
        return leftOut.clone();
    }

    /** Deletes the records as the user, raising AccessDeniedException when the user may not delete one of their objects. */
    public static void remove(List<SObject> records)
    {
        for (SObjectType type : typesOf(records))
        {
            if (!type.getDescribe().isDeletable()) { throw new AccessDeniedException(String.valueOf(type), null, Access.REMOVE, new List<String>()); }
        }
        Database.delete(records, true, AccessLevel.USER_MODE);
        for (SObject record : records) { remembered.remove(record.Id); }
    }

    /** A save that writes what the user may edit and leaves out the rest, listing it on lastLeftOut(). */
    public class LeavingOutUneditable
    {
        private LeavingOutUneditable() {}

        /** Inserts the records with no Id and updates the rest, all or nothing, without the fields the user may not edit. */
        public void save(List<SObject> records)
        {
            saveWritable(records, true);
        }
    }

    private static Exception accessDeniedOr(QueryException failure)
    {
        Map<String, Set<String>> inaccessible = failure.getInaccessibleFields();
        for (String objectName : inaccessible.keySet())
        {
            if (isClosedToUser(objectName)) { return new AccessDeniedException(objectName, null, Access.READ, new List<String>()); }
        }
        if (!inaccessible.isEmpty()) { return fieldsDenied(inaccessible, Access.READ); }
        Matcher unsupported = UNSUPPORTED_OBJECT.matcher(failure.getMessage());
        if (unsupported.find() && isClosedToUser(unsupported.group(1)))
        {
            return new AccessDeniedException(unsupported.group(1), null, Access.READ, new List<String>());
        }
        return failure;
    }

    private static Boolean isClosedToUser(String objectName)
    {
        SObjectType type = Schema.getGlobalDescribe().get(objectName);
        return type != null && !type.getDescribe().isAccessible();
    }

    private static void saveWritable(List<SObject> records, Boolean leavingOut)
    {
        leftOut = new Set<String>();
        List<SObject> inserts = new List<SObject>();
        List<SObject> updates = new List<SObject>();
        Map<String, Set<String>> notCreatable = new Map<String, Set<String>>();
        Map<String, Set<String>> notEditable = new Map<String, Set<String>>();
        for (SObject record : records)
        {
            if (record.Id == null) { inserts.add(fieldsToWrite(record, notCreatable)); }
            else { updates.add(fieldsToWrite(record, notEditable)); }
        }
        inserts = checkedForUser(inserts, AccessType.CREATABLE, leavingOut, notCreatable);
        updates = checkedForUser(updates, AccessType.UPDATABLE, leavingOut, notEditable);
        writeAllOrNothing(inserts, updates);
        Integer next = 0;
        for (SObject record : records)
        {
            if (record.Id == null) { record.Id = inserts[next++].Id; }
        }
        rememberWritten(inserts);
        rememberWritten(updates);
    }

    private static SObject fieldsToWrite(SObject record, Map<String, Set<String>> refused)
    {
        SObjectType type = record.getSObjectType();
        if (!fieldsByType.containsKey(type)) { fieldsByType.put(type, type.getDescribe().fields.getMap()); }
        Map<String, SObjectField> fields = fieldsByType.get(type);
        SObject known = record.Id == null ? null : remembered.get(record.Id);
        Map<String, Object> knownValues = known == null ? null : known.getPopulatedFieldsAsMap();
        // The Id goes on last: Apex refuses a field writable only on create on a record that already has one.
        SObject written = type.newSObject();
        Map<String, Object> values = record.getPopulatedFieldsAsMap();
        for (String fieldName : values.keySet())
        {
            SObjectField field = fields.get(fieldName);
            if (field == null || isMaintainedBySalesforce(type, field)) { continue; }
            Object value = values.get(fieldName);
            if (knownValues != null && isUnchanged(knownValues, fieldName, value)) { continue; }
            try
            {
                written.put(field, value);
            }
            catch (SObjectException notWritable)
            {
                // A field nobody may write, such as Opportunity.ExpectedRevenue, is refused like a missing permission.
                addRefused(refused, String.valueOf(type), new Set<String>{ String.valueOf(field) });
            }
        }
        written.Id = record.Id;
        return written;
    }

    private static Boolean isMaintainedBySalesforce(SObjectType type, SObjectField field)
    {
        String key = type + '.' + field;
        if (!maintainedBySalesforce.containsKey(key))
        {
            DescribeFieldResult describe = field.getDescribe();
            maintainedBySalesforce.put(key, AUDIT_FIELDS.contains(describe.getName().toLowerCase())
                || describe.isCalculated() || describe.isAutoNumber());
        }
        return maintainedBySalesforce.get(key);
    }

    private static Boolean isUnchanged(Map<String, Object> knownValues, String fieldName, Object value)
    {
        if (!knownValues.containsKey(fieldName)) { return false; }
        Object knownValue = knownValues.get(fieldName);
        if (value instanceof String && knownValue instanceof String) { return ((String) value).equals((String) knownValue); }
        return value == knownValue;
    }

    private static List<SObject> checkedForUser(List<SObject> records, AccessType writing, Boolean leavingOut, Map<String, Set<String>> refused)
    {
        if (records.isEmpty()) { return records; }
        for (SObjectType type : typesOf(records))
        {
            DescribeSObjectResult describe = type.getDescribe();
            Boolean allowed = writing == AccessType.CREATABLE ? describe.isCreateable() : describe.isUpdateable();
            if (!allowed)
            {
                throw new AccessDeniedException(String.valueOf(type), null, writing == AccessType.CREATABLE ? Access.CREATE : Access.EDIT, new List<String>());
            }
        }
        SObjectAccessDecision decision = Security.stripInaccessible(writing, records);
        Map<String, Set<String>> removed = decision.getRemovedFields();
        for (String objectName : removed.keySet()) { addRefused(refused, objectName, removed.get(objectName)); }
        if (refused.isEmpty()) { return records; }
        if (!leavingOut) { throw fieldsDenied(refused, Access.EDIT); }
        leftOut.addAll(qualifiedNames(refused));
        return decision.getRecords();
    }

    private static void addRefused(Map<String, Set<String>> refused, String objectName, Set<String> fieldNames)
    {
        if (!refused.containsKey(objectName)) { refused.put(objectName, new Set<String>()); }
        refused.get(objectName).addAll(fieldNames);
    }

    private static void writeAllOrNothing(List<SObject> inserts, List<SObject> updates)
    {
        Savepoint beforeSave = !inserts.isEmpty() && !updates.isEmpty() ? Database.setSavepoint() : null;
        try
        {
            if (!inserts.isEmpty()) { Database.insert(inserts, true, AccessLevel.USER_MODE); }
            if (!updates.isEmpty()) { Database.update(updates, true, AccessLevel.USER_MODE); }
        }
        catch (Exception failure)
        {
            if (beforeSave != null) { Database.rollback(beforeSave); }
            throw failure;
        }
    }

    private static void rememberWritten(List<SObject> written)
    {
        for (SObject record : written)
        {
            SObject known = remembered.get(record.Id);
            if (known == null)
            {
                remembered.put(record.Id, record.clone(true, false, true, true));
                continue;
            }
            Map<String, Object> values = record.getPopulatedFieldsAsMap();
            for (String fieldName : values.keySet()) { known.put(fieldName, values.get(fieldName)); }
        }
    }

    private static Set<SObjectType> typesOf(List<SObject> records)
    {
        Set<SObjectType> types = new Set<SObjectType>();
        for (SObject record : records) { types.add(record.getSObjectType()); }
        return types;
    }

    private static AccessDeniedException fieldsDenied(Map<String, Set<String>> fieldsByObject, Access missing)
    {
        List<String> names = qualifiedNames(fieldsByObject);
        names.sort();
        String first = names[0];
        return new AccessDeniedException(first.substringBefore('.'), first.substringAfter('.'), missing, names);
    }

    private static List<String> qualifiedNames(Map<String, Set<String>> fieldsByObject)
    {
        List<String> names = new List<String>();
        for (String objectName : fieldsByObject.keySet())
        {
            for (String fieldName : fieldsByObject.get(objectName)) { names.add(objectName + '.' + fieldName); }
        }
        return names;
    }

    /** Raised when the user is missing the permission to read, create, edit or delete an object or field. */
    public class AccessDeniedException extends Exception
    {
        /** The API name of the object, such as Opportunity. */
        public String objectName { get; private set; }
        /** The API name of the first field refused, or null when the whole object is closed to the user. */
        public String fieldName { get; private set; }
        /** The kind of access the user is missing. */
        public Access access { get; private set; }
        /** Every field refused, as Object.Field, in name order; empty when the whole object is closed. */
        public List<String> deniedFields { get; private set; }

        private AccessDeniedException(String objectName, String fieldName, Access missing, List<String> deniedFields)
        {
            this(sentence(objectName, fieldName, missing, deniedFields.size()));
            this.objectName = objectName;
            this.fieldName = fieldName;
            this.access = missing;
            this.deniedFields = deniedFields;
        }
    }

    private static String sentence(String objectName, String fieldName, Access missing, Integer fieldCount)
    {
        String verb = missing == Access.REMOVE ? 'delete' : missing.name().toLowerCase();
        String what = fieldName == null ? objectName : objectName + '.' + fieldName;
        Integer more = fieldCount - 1;
        String rest = more < 1 ? '' : ' and ' + more + (more == 1 ? ' more field' : ' more fields');
        return 'You cannot ' + verb + ' ' + what + rest + '.';
    }
}
