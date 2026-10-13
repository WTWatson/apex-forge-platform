@IsTest
private class ForgeDataBuilderTest {

    @IsTest
    static void buildSetsFieldsLiterally()
    {
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'Acme')
            .with(Account.Industry, 'Technology')
            .build();

        Assert.areEqual('Acme', a.Name);
        Assert.areEqual('Technology', a.Industry);
    }

    @IsTest
    static void buildAutoFillsRequiredStringField()
    {
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType).build();

        Assert.isNotNull(c.LastName, 'Required string should be auto-filled');
        Assert.isTrue(c.LastName.length() > 0);
    }

    @IsTest
    static void buildRespectsExplicitOverAutoFill()
    {
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType)
            .with(Contact.LastName, 'Explicit')
            .build();

        Assert.areEqual('Explicit', c.LastName,
            'Explicit with() should win over auto-fill');
    }

    @IsTest
    static void countBuildsNRecords()
    {
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'A')
            .count(3)
            .buildList();

        Assert.areEqual(3, accts.size());
    }

    @IsTest
    static void countWithProviderAssignsPerIndexValues()
    {
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, ForgeDataSeeder.sequence('Acct'))
            .count(3)
            .buildList();

        Assert.areEqual('Acct 1', ((Account) accts[0]).Name);
        Assert.areEqual('Acct 2', ((Account) accts[1]).Name);
        Assert.areEqual('Acct 3', ((Account) accts[2]).Name);
    }

    @IsTest
    static void parentWiresLookup()
    {
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType).persist();

        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType)
            .with(Contact.LastName, 'Child')
            .parent(Contact.AccountId, a)
            .build();

        Assert.areEqual(a.Id, c.AccountId,
            'parent() should set the FK to the parent Id');
    }

    @IsTest
    static void parentRejectsNonReferenceField()
    {
        Account saved = (Account) ForgeDataBuilder.of(Account.SObjectType).persist();

        try {
            ForgeDataBuilder.of(Contact.SObjectType).parent(Contact.LastName, saved);
            Assert.fail('Expected ConfigException when FK is not a REFERENCE');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('REFERENCE'));
        }
    }

    @IsTest
    static void parentRejectsWrongSObjectType()
    {
        Contact savedContact = (Contact) ForgeDataBuilder.of(Contact.SObjectType).persist();

        try {
            ForgeDataBuilder.of(Contact.SObjectType)
                .parent(Contact.AccountId, savedContact);
            Assert.fail('Expected ConfigException when parent type does not match FK reference');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('not a valid reference'));
        }
    }

    @IsTest
    static void parentThrowsWhenParentUnsaved()
    {
        Account a = new Account(Name = 'Unsaved');

        try {
            ForgeDataBuilder.of(Contact.SObjectType).parent(Contact.AccountId, a);
            Assert.fail('Expected ConfigException when parent Id is null');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('Id is null'));
        }
    }

    @IsTest
    static void withThrowsWhenFieldNotOnSObject()
    {
        try {
            ForgeDataBuilder.of(Account.SObjectType).with(Contact.LastName, 'X');
            Assert.fail('Expected ConfigException when field belongs to another SObject');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('does not belong to'));
        }
    }

    @IsTest
    static void persistInsertsRecord()
    {
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'Persisted')
            .persist();

        Assert.isNotNull(a.Id, 'persist() should populate Id');

        Account loaded = [SELECT Name FROM Account WHERE Id = :a.Id];
        Assert.areEqual('Persisted', loaded.Name);
    }

    @IsTest
    static void persistListInsertsAll()
    {
        List<SObject> accts = ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, ForgeDataSeeder.sequence('Bulk'))
            .count(3)
            .persistList();

        for (SObject s : accts) {
            Assert.isNotNull(s.Id);
        }
        Assert.areEqual(3, [SELECT COUNT() FROM Account WHERE Name LIKE 'Bulk %']);
    }

    @IsTest
    static void autoFillSkipsReferenceFields()
    {
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType).build();

        Assert.isNull(c.AccountId, 'REFERENCE fields must not be auto-filled');
    }

    @IsTest
    static void autoFillCanBeDisabled()
    {
        Contact c = (Contact) ForgeDataBuilder.of(Contact.SObjectType)
            .autoFill(false)
            .build();

        Assert.isNull(c.LastName,
            'autoFill(false) should leave required fields empty');
    }

    @IsTest
    static void buildThrowsWhenCountGreaterThanOne()
    {
        try {
            ForgeDataBuilder.of(Account.SObjectType).count(2).build();
            Assert.fail('Expected ConfigException when build() called with count > 1');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('buildList'));
        }
    }

    @IsTest
    static void persistThrowsWhenCountGreaterThanOne()
    {
        try {
            ForgeDataBuilder.of(Account.SObjectType).count(2).persist();
            Assert.fail('Expected ConfigException when persist() called with count > 1');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('persistList'));
        }
    }

    @IsTest
    static void countRejectsZeroOrNegative()
    {
        try {
            ForgeDataBuilder.of(Account.SObjectType).count(0);
            Assert.fail('Expected ConfigException for count < 1');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('>= 1'));
        }
    }

    @IsTest
    static void ofRejectsNull()
    {
        try {
            ForgeDataBuilder.of(null);
            Assert.fail('Expected ConfigException for null SObjectType');
        } catch (ForgeDataBuilder.ConfigException e) {
            Assert.isTrue(e.getMessage().contains('required'));
        }
    }

    @IsTest
    static void autoFillSatisfiesOpportunityRequiredFields()
    {
        Opportunity o = (Opportunity) ForgeDataBuilder.of(Opportunity.SObjectType).persist();

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
        List<SObject> contacts = ForgeDataBuilder.of(Contact.SObjectType)
            .with(Contact.FirstName, ForgeDataSeeder.firstNames())
            .with(Contact.LastName, ForgeDataSeeder.lastNames())
            .count(2)
            .buildList();

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
        Attachment att = (Attachment) ForgeDataBuilder.of(Attachment.SObjectType).build();

        Assert.isNotNull(att);
        Assert.isNull(att.Body,
            'BASE64 fields should not be auto-filled — falls through to null');
    }

    @IsTest
    static void laterWithOverwritesEarlier()
    {
        Account a = (Account) ForgeDataBuilder.of(Account.SObjectType)
            .with(Account.Name, 'First')
            .with(Account.Name, 'Second')
            .build();

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
