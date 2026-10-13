@IsTest
private class ForgeDataBuilderTest {

    @IsTest
    static void buildSetsFieldsLiterally()
    {
        Test.startTest();
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'Acme')
            .with(Account.Industry, 'Technology')
            .build();
        Test.stopTest();

        Assert.areEqual('Acme', a.Name);
        Assert.areEqual('Technology', a.Industry);
    }

    @IsTest
    static void buildAutoFillsRequiredStringField()
    {
        Test.startTest();
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType).build();
        Test.stopTest();

        Assert.isNotNull(c.LastName, 'Required string should be auto-filled');
        Assert.isTrue(c.LastName.length() > 0);
    }

    @IsTest
    static void buildRespectsExplicitOverAutoFill()
    {
        Test.startTest();
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType)
            .with(Contact.LastName, 'Explicit')
            .build();
        Test.stopTest();

        Assert.areEqual('Explicit', c.LastName,
            'Explicit with() should win over auto-fill');
    }

    @IsTest
    static void countBuildsNRecords()
    {
        Test.startTest();
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'A')
            .count(3)
            .buildList();
        Test.stopTest();

        Assert.areEqual(3, accts.size());
    }

    @IsTest
    static void countWithProviderAssignsPerIndexValues()
    {
        Test.startTest();
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, ForgeDataSeeder.sequence('Acct'))
            .count(3)
            .buildList();
        Test.stopTest();

        Assert.areEqual('Acct 1', ((Account) accts[0]).Name);
        Assert.areEqual('Acct 2', ((Account) accts[1]).Name);
        Assert.areEqual('Acct 3', ((Account) accts[2]).Name);
    }

    @IsTest
    static void buildListGivesEachOf200RecordsItsProviderValue()
    {
        Test.startTest();
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, ForgeDataSeeder.sequence('Acct'))
            .with(Account.Industry, 'Technology')
            .count(200)
            .buildList();
        Test.stopTest();

        Assert.areEqual(200, accts.size());
        for (Integer index = 0; index < 200; index++) {
            Account built = (Account) accts[index];
            Assert.areEqual('Acct ' + (index + 1), built.Name);
            Assert.areEqual('Technology', built.Industry);
            Assert.isNull(built.Id, 'buildList() must not insert');
        }
    }

    @IsTest
    static void persistListInserts200Records()
    {
        Test.startTest();
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, ForgeDataSeeder.sequence('Bulk'))
            .count(200)
            .persistList();
        Test.stopTest();

        Assert.areEqual(200, accts.size());
        for (SObject s : accts) {
            Assert.isNotNull(s.Id);
        }
        Assert.areEqual(200, [SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk %']);
    }

    @IsTest
    static void autoFillNumbersRequiredTextAcross200Records()
    {
        Test.startTest();
        List<SObject> contacts = ForgeDataBuilder.of(Contact.SObjectType)
            .count(200)
            .persistList();
        Test.stopTest();

        Set<String> lastNames = new Set<String>();
        for (SObject s : contacts) {
            lastNames.add(((Contact) s).LastName);
        }
        Assert.areEqual(200, lastNames.size(), 'Each auto-filled LastName should be numbered apart');
        Assert.areEqual('LastName 1', ((Contact) contacts[0]).LastName);
        Assert.areEqual('LastName 200', ((Contact) contacts[199]).LastName);
        Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE LastName LIKE 'LastName %']);
    }

    @IsTest
    static void parentWiresLookup()
    {
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType).persist();

        Test.startTest();
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType)
            .with(Contact.LastName, 'Child')
            .parent(Contact.AccountId, a)
            .build();
        Test.stopTest();

        Assert.areEqual(a.Id, c.AccountId,
            'parent() should set the FK to the parent Id');
    }

    @IsTest
    static void parentWiresLookupOn200Records()
    {
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType).persist();

        Test.startTest();
        List<SObject> contacts = ForgeDataBuilder.of(Contact.SObjectType)
            .parent(Contact.AccountId, a)
            .count(200)
            .persistList();
        Test.stopTest();

        Assert.areEqual(200, [SELECT COUNT() FROM Contact WHERE AccountId = :a.Id]);
        Assert.areEqual(200, contacts.size());
    }

    @IsTest
    static void parentRejectsNonReferenceField()
    {
        Account saved = (Account) ForgeDataBuilder.of(Account.SObjectType).persist();

        Test.startTest();
        try {
            ForgeDataBuilder.of(Contact.SObjectType).parent(Contact.LastName, saved);
            Assert.fail('Expected ConfigException when FK is not a REFERENCE');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('REFERENCE'));
        }
        Test.stopTest();
    }

    @IsTest
    static void parentRejectsWrongSObjectType()
    {
        Contact savedContact = (Contact) ForgeDataBuilder.of(Contact.SObjectType).persist();

        Test.startTest();
        try {
            ForgeDataBuilder.of(Contact.SObjectType)
                .parent(Contact.AccountId, savedContact);
            Assert.fail('Expected ConfigException when parent type does not match FK reference');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('not a valid reference'));
        }
        Test.stopTest();
    }

    @IsTest
    static void parentThrowsWhenParentUnsaved()
    {
        Account a = new Account(Name = 'Unsaved');

        Test.startTest();
        try {
            ForgeDataBuilder.of(Contact.SObjectType).parent(Contact.AccountId, a);
            Assert.fail('Expected ConfigException when parent Id is null');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('Id is null'));
        }
        Test.stopTest();
    }

    @IsTest
    static void withThrowsWhenFieldNotOnSObject()
    {
        Test.startTest();
        try {
            ForgeDataBuilder.of(Account.SObjectType).with(Contact.LastName, 'X');
            Assert.fail('Expected ConfigException when field belongs to another SObject');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('does not belong to'));
        }
        Test.stopTest();
    }

    @IsTest
    static void persistInsertsRecord()
    {
        Test.startTest();
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'Persisted')
            .persist();
        Test.stopTest();

        Assert.isNotNull(a.Id, 'persist() should populate Id');

        Account loaded = [SELECT Name FROM Account WHERE Id = :a.Id];
        Assert.areEqual('Persisted', loaded.Name);
    }

    @IsTest
    static void persistListInsertsAll()
    {
        Test.startTest();
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, ForgeDataSeeder.sequence('Bulk'))
            .count(3)
            .persistList();
        Test.stopTest();

        for (SObject s : accts) {
            Assert.isNotNull(s.Id);
        }
        Assert.areEqual(3, [SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk %']);
    }

    @IsTest
    static void autoFillSkipsReferenceFields()
    {
        Test.startTest();
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType).build();
        Test.stopTest();

        Assert.isNull(c.AccountId, 'REFERENCE fields must not be auto-filled');
    }

    @IsTest
    static void autoFillCanBeDisabled()
    {
        Test.startTest();
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType)
            .autoFill(false)
            .build();
        Test.stopTest();

        Assert.isNull(c.LastName,
            'autoFill(false) should leave required fields empty');
    }

    @IsTest
    static void buildThrowsWhenCountGreaterThanOne()
    {
        Test.startTest();
        try {
            ForgeDataBuilder.of(Account.SObjectType).count(2).build();
            Assert.fail('Expected ConfigException when build() called with count > 1');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('buildList'));
        }
        Test.stopTest();
    }

    @IsTest
    static void persistThrowsWhenCountGreaterThanOne()
    {
        Test.startTest();
        try {
            ForgeDataBuilder.of(Account.SObjectType).count(2).persist();
            Assert.fail('Expected ConfigException when persist() called with count > 1');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('persistList'));
        }
        Test.stopTest();
    }

    @IsTest
    static void countRejectsZeroOrNegative()
    {
        Test.startTest();
        try {
            ForgeDataBuilder.of(Account.SObjectType).count(0);
            Assert.fail('Expected ConfigException for count < 1');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('>= 1'));
        }
        Test.stopTest();
    }

    @IsTest
    static void ofRejectsNull()
    {
        Test.startTest();
        try {
            ForgeDataBuilder.of(null);
            Assert.fail('Expected ConfigException for null SObjectType');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void autoFillSatisfiesOpportunityRequiredFields()
    {
        Test.startTest();
        Opportunity o = (Opportunity) ForgeDataBuilder.of(Opportunity.SObjectType).persist();
        Test.stopTest();

        Assert.isNotNull(o.Id);

        Opportunity loaded = [
            SELECT Name, StageName, CloseDate FROM Opportunity WHERE Id = :o.Id
        ];
        Assert.isNotNull(loaded.Name);
        Assert.isNotNull(loaded.StageName);
        Assert.isNotNull(loaded.CloseDate);
    }

    @IsTest
    static void countWithEmberCycleProviders()
    {
        Test.startTest();
        List<SObject> contacts = ForgeDataBuilder.of(Contact.SObjectType)
            .with(Contact.FirstName, ForgeDataSeeder.firstNames())
            .with(Contact.LastName, ForgeDataSeeder.lastNames())
            .count(2)
            .buildList();
        Test.stopTest();

        Assert.areEqual(2, contacts.size());

        Contact c0 = (Contact) contacts[0];
        Contact c1 = (Contact) contacts[1];
        Assert.isNotNull(c0.FirstName);
        Assert.isNotNull(c0.LastName);
        Assert.areNotEqual(c0.FirstName, c1.FirstName);
    }

    @IsTest
    static void autoFillLeavesUnsupportedDisplayTypesNull()
    {
        Test.startTest();
        Attachment att = (Attachment) ForgeDataBuilder.of(Attachment.SObjectType).build();
        Test.stopTest();

        Assert.isNotNull(att);
        Assert.isNull(att.Body,
            'BASE64 fields should not be auto-filled — falls through to null');
    }

    @IsTest
    static void laterWithOverwritesEarlier()
    {
        Test.startTest();
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'First')
            .with(Account.Name, 'Second')
            .build();
        Test.stopTest();

        Assert.areEqual('Second', a.Name,
            'Later with() call should overwrite earlier value');
    }

    @IsTest
    static void fieldBelongsToTellsSameNamedFieldsApart()
    {
        Assert.isTrue(ForgeDataBuilder.fieldBelongsTo(Account.SObjectType, Account.Name));
        Assert.isFalse(ForgeDataBuilder.fieldBelongsTo(Account.SObjectType, Contact.Name),
            'A field of the same name on another object does not belong');
        Assert.isFalse(ForgeDataBuilder.fieldBelongsTo(Account.SObjectType, Contact.LastName));
    }

    @IsTest
    static void repeatedBuildsOfOneObjectEachFillWhatIsMissing()
    {
        Test.startTest();
        Contact filled = (Contact) ForgeDataBuilder.of(Contact.SObjectType).build();
        Contact named = (Contact) ForgeDataBuilder.of(Contact.SObjectType)
            .with(Contact.LastName, 'Smith')
            .build();
        List<SObject> several = ForgeDataBuilder.of(Contact.SObjectType)
            .count(2)
            .buildList();
        Test.stopTest();

        Assert.areEqual('Test', filled.LastName);
        Assert.areEqual('Smith', named.LastName,
            'An explicit value on a later build should win over the remembered required field');
        Assert.areEqual('LastName 2', ((Contact) several[1]).LastName);
    }

    @IsTest
    static void bulkAutoFillNamesEachRecordAndSharesTheStage()
    {
        Test.startTest();
        List<SObject> opps = ForgeDataBuilder.of(Opportunity.SObjectType)
            .count(200)
            .buildList();
        Test.stopTest();

        Opportunity first = (Opportunity) opps[0];
        Opportunity last = (Opportunity) opps[199];
        Assert.areEqual(200, opps.size());
        Assert.areEqual('Name 1', first.Name);
        Assert.areEqual('Name 200', last.Name);
        Assert.isNotNull(first.StageName);
        Assert.areEqual(first.StageName, last.StageName,
            'Every record should get the same first active stage');
        Assert.areEqual(Date.today(), last.CloseDate);
    }
}
