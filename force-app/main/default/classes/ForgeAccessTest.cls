@IsTest
private class ForgeAccessTest
{
    // These tests use only standard Account fields and the Standard User profile, so
    // they run in any org that has the platform. The permission-set cases, with a
    // formula, a roll-up, an auto-number and fields a rep may not read or edit, are
    // tested in test-support (ForgeAccessOnOpportunityTest).

    private static User aStandardUser()
    {
        User rep = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            LastName = 'Rep',
            Alias = 'rep',
            Email = 'rep@example.com',
            Username = 'forge.access.' + System.currentTimeMillis() + '@example.com',
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert rep;
        return rep;
    }

    private static List<Account> accountsOwnedBy(User rep, Integer count)
    {
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < count; i++)
        {
            accounts.add(new Account(Name = 'Customer ' + i, Phone = '0100', Website = 'example.com', OwnerId = rep.Id));
        }
        insert accounts;
        return accounts;
    }

    private static Map<String, Object> binds(String name, Object value)
    {
        return new Map<String, Object>{ name => value };
    }

    private static Set<String> namesOfAccountsAdded()
    {
        Set<String> names = new Set<String>();
        for (Account account : [SELECT Name FROM Account WHERE Name LIKE 'Added%']) { names.add(account.Name); }
        return names;
    }

    @IsTest
    static void queryReturnsAListOfTheQueriedObjectSoTheCastHolds()
    {
        User rep = aStandardUser();
        accountsOwnedBy(rep, 1);
        List<SObject> records;
        Test.startTest();
        System.runAs(rep)
        {
            records = ForgeAccess.query('SELECT Id, Name FROM Account WHERE OwnerId = :ownerId', binds('ownerId', rep.Id));
        }
        Test.stopTest();
        Assert.isInstanceOfType(records, List<Account>.class);
        List<Account> accounts = (List<Account>) records;
        Assert.areEqual('Customer 0', accounts[0].Name);
    }

    @IsTest
    static void aMistakeInTheQueryIsRaisedAsSalesforceGivesIt()
    {
        User rep = aStandardUser();
        Test.startTest();
        System.runAs(rep)
        {
            try
            {
                ForgeAccess.query('SELECT Idd FROM Account', new Map<String, Object>());
                Assert.fail('A query with no such field should fail.');
            }
            catch (QueryException failure)
            {
                Assert.isTrue(failure.getMessage().contains('Idd'), failure.getMessage());
            }
        }
        Test.stopTest();
    }

    @IsTest
    static void newRecordsAreInsertedAndGetTheirIds()
    {
        User rep = aStandardUser();
        List<Account> accounts = new List<Account>();
        for (Integer i = 0; i < 200; i++) { accounts.add(new Account(Name = 'New ' + i)); }
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.save(accounts);
        }
        Test.stopTest();
        for (Account account : accounts) { Assert.isNotNull(account.Id); }
        Assert.areEqual(200, [SELECT COUNT() FROM Account WHERE Name LIKE 'New %' AND OwnerId = :rep.Id]);
    }

    @IsTest
    static void aRecordReadEarlierWritesOnlyTheFieldsChangedSince()
    {
        User rep = aStandardUser();
        accountsOwnedBy(rep, 200);
        Test.startTest();
        System.runAs(rep)
        {
            List<Account> accounts = (List<Account>) ForgeAccess.query(
                'SELECT Id, Name, Phone, Website FROM Account WHERE OwnerId = :ownerId',
                binds('ownerId', rep.Id)
            );
            List<Account> changedMeanwhile = new List<Account>();
            for (Account account : accounts)
            {
                changedMeanwhile.add(new Account(Id = account.Id, Phone = '0199'));
                account.Website = 'example.org';
            }
            update changedMeanwhile;
            ForgeAccess.save(accounts);
        }
        Test.stopTest();
        for (Account account : [SELECT Phone, Website FROM Account WHERE OwnerId = :rep.Id])
        {
            Assert.areEqual('example.org', account.Website, 'The changed field is written.');
            Assert.areEqual('0199', account.Phone, 'The unchanged field is not written back over a later change.');
        }
    }

    @IsTest
    static void aChangeOnlyInLetterCaseIsWritten()
    {
        User rep = aStandardUser();
        accountsOwnedBy(rep, 1);
        Test.startTest();
        System.runAs(rep)
        {
            Account account = (Account) ForgeAccess.query('SELECT Id, Website FROM Account WHERE OwnerId = :ownerId', binds('ownerId', rep.Id))[0];
            account.Website = 'EXAMPLE.com';
            ForgeAccess.save(new List<Account>{ account });
        }
        Test.stopTest();
        Assert.isTrue([SELECT Website FROM Account WHERE OwnerId = :rep.Id].Website.equals('EXAMPLE.com'));
    }

    @IsTest
    static void aClearedFieldIsWrittenAsEmpty()
    {
        User rep = aStandardUser();
        Account existing = accountsOwnedBy(rep, 1)[0];
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.save(new List<Account>{ new Account(Id = existing.Id, Website = null) });
        }
        Test.stopTest();
        Assert.isNull([SELECT Website FROM Account WHERE Id = :existing.Id].Website);
    }

    @IsTest
    static void auditFieldsSentBackFromAComponentAreNeitherWrittenNorRefused()
    {
        User rep = aStandardUser();
        Account existing = accountsOwnedBy(rep, 1)[0];
        Account stored = [SELECT Id, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, SystemModstamp FROM Account WHERE Id = :existing.Id];
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(stored));
        sent.put('Phone', '0123');
        Account fromComponent = (Account) JSON.deserialize(JSON.serialize(sent), Account.class);
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.save(new List<Account>{ fromComponent });
        }
        Test.stopTest();
        Account saved = [SELECT Phone, CreatedDate FROM Account WHERE Id = :existing.Id];
        Assert.areEqual('0123', saved.Phone);
        Assert.areEqual(stored.CreatedDate, saved.CreatedDate);
    }

    @IsTest
    static void aFailedUpdateRollsBackTheInsertsOfTheSameSave()
    {
        User rep = aStandardUser();
        Account existing = accountsOwnedBy(rep, 1)[0];
        Account added = new Account(Name = 'Added');
        Account emptied = new Account(Id = existing.Id, Name = null);
        Test.startTest();
        System.runAs(rep)
        {
            try
            {
                ForgeAccess.save(new List<Account>{ added, emptied });
                Assert.fail('An Account with no name should not save.');
            }
            catch (DmlException failure)
            {
                Assert.areEqual(StatusCode.REQUIRED_FIELD_MISSING, failure.getDmlType(0));
            }
        }
        Test.stopTest();
        Assert.isNull(added.Id, 'No Id is set after a rollback.');
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE Name = 'Added']);
        Assert.areEqual('Customer 0', [SELECT Name FROM Account WHERE Id = :existing.Id].Name);
    }

    @IsTest
    static void insertsAndUpdatesSaveTogether()
    {
        User rep = aStandardUser();
        Account existing = accountsOwnedBy(rep, 1)[0];
        Account added = new Account(Name = 'Added');
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.save(new List<Account>{ added, new Account(Id = existing.Id, Name = 'Renamed') });
        }
        Test.stopTest();
        Assert.isNotNull(added.Id);
        Assert.areEqual('Renamed', [SELECT Name FROM Account WHERE Id = :existing.Id].Name);
    }

    @IsTest
    static void manySavesThatInsertAndUpdateRunInOneTransaction()
    {
        User rep = aStandardUser();
        Account existing = accountsOwnedBy(rep, 1)[0];
        Test.startTest();
        System.runAs(rep)
        {
            for (Integer save = 1; save <= 8; save++)
            {
                ForgeAccess.save(new List<Account>{ new Account(Name = 'Added ' + save), new Account(Id = existing.Id, Name = 'Renamed ' + save) });
            }
        }
        Test.stopTest();
        Assert.areEqual(8, [SELECT COUNT() FROM Account WHERE Name LIKE 'Added %']);
        Assert.areEqual('Renamed 8', [SELECT Name FROM Account WHERE Id = :existing.Id].Name);
    }

    @IsTest
    static void failedSavesThatInsertAndUpdateLeaveTheTransactionFreeToSaveAgain()
    {
        User rep = aStandardUser();
        Account existing = accountsOwnedBy(rep, 1)[0];
        Integer failures = 0;
        Test.startTest();
        System.runAs(rep)
        {
            for (Integer save = 1; save <= 6; save++)
            {
                try
                {
                    ForgeAccess.save(new List<Account>{ new Account(Name = 'Added ' + save), new Account(Id = existing.Id, Name = null) });
                }
                catch (DmlException failure)
                {
                    failures++;
                }
            }
            ForgeAccess.save(new List<Account>{ new Account(Name = 'Added after'), new Account(Id = existing.Id, Name = 'Renamed') });
        }
        Test.stopTest();
        Assert.areEqual(6, failures);
        Assert.areEqual(new Set<String>{ 'Added after' }, namesOfAccountsAdded());
        Assert.areEqual('Renamed', [SELECT Name FROM Account WHERE Id = :existing.Id].Name);
    }

    @IsTest
    static void removeDeletesTheRecords()
    {
        User rep = aStandardUser();
        List<Account> accounts = accountsOwnedBy(rep, 200);
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.remove(accounts);
        }
        Test.stopTest();
        Assert.areEqual(0, [SELECT COUNT() FROM Account WHERE OwnerId = :rep.Id]);
    }

    @IsTest
    static void aRecordSavedEarlierWritesOnlyWhatChangesAfter()
    {
        User rep = aStandardUser();
        Test.startTest();
        System.runAs(rep)
        {
            Account account = new Account(Name = 'Saved', Phone = '0100');
            ForgeAccess.save(new List<Account>{ account });
            update new Account(Id = account.Id, Phone = '0199');
            account.Website = 'example.org';
            ForgeAccess.save(new List<Account>{ account });
        }
        Test.stopTest();
        Account saved = [SELECT Phone, Website FROM Account WHERE Name = 'Saved'];
        Assert.areEqual('example.org', saved.Website);
        Assert.areEqual('0199', saved.Phone);
    }
}
