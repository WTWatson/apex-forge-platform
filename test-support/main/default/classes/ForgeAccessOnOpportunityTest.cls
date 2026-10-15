/**
 * This file is part of the Forge Platform project
 *
 * Test support only: ForgeAccess as a sales rep meets it, a Standard User with the
 * Forge_Test_Access permission set, on Opportunity fields of every kind the save
 * decides about: a formula, a roll-up, an auto-number, a field the rep may only
 * read, one the rep may not read, a field writable on create but not on update, and
 * fields nobody may write.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
@IsTest
private class ForgeAccessOnOpportunityTest
{

    private static User aUser(Boolean withRepPermissions)
    {
        User person = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User'].Id,
            LastName = withRepPermissions ? 'Rep' : 'Outsider',
            Alias = 'forge',
            Email = 'forge.access@example.com',
            Username = 'forge.access.' + System.currentTimeMillis() + '.' + Crypto.getRandomInteger() + '@example.com',
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId()))
        {
            insert person;
            if (withRepPermissions)
            {
                insert new PermissionSetAssignment(
                    AssigneeId = person.Id,
                    PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Forge_Test_Access'].Id
                );
            }
        }
        return person;
    }

    private static User aSalesRep() { return aUser(true); }

    private static User anOutsider() { return aUser(false); }

    private static List<Opportunity> opportunitiesOwnedBy(User owner, Integer count)
    {
        List<Opportunity> opportunities = new List<Opportunity>();
        for (Integer i = 0; i < count; i++)
        {
            opportunities.add(new Opportunity(
                Name = 'Deal ' + i,
                StageName = 'Prospecting',
                CloseDate = Date.today().addDays(30),
                Forge_Test_Margin__c = 5,
                Forge_Test_Notes__c = 'First call',
                OwnerId = owner.Id
            ));
        }
        insert opportunities;
        return opportunities;
    }

    private static Forge_Test_Line__c aLineOn(Opportunity opportunity)
    {
        Forge_Test_Line__c line = new Forge_Test_Line__c(Name = 'Line', Opportunity__c = opportunity.Id, Hours__c = 1);
        insert line;
        return line;
    }

    private static Map<String, Object> ownedBy(User owner)
    {
        return new Map<String, Object>{ 'ownerId' => owner.Id };
    }

    private static Opportunity sentBackWhole(Opportunity opportunity)
    {
        Opportunity stored = [SELECT Id, StageName, IsClosed, ExpectedRevenue FROM Opportunity WHERE Id = :opportunity.Id];
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(stored));
        sent.put('StageName', 'Qualification');
        sent.put('ExpectedRevenue', 100);
        return (Opportunity) JSON.deserialize(JSON.serialize(sent), Opportunity.class);
    }

    @IsTest
    static void aFieldTheRepMayNotReadRefusesTheQuery()
    {
        User rep = aSalesRep();
        opportunitiesOwnedBy(rep, 1);
        List<String> messages = new List<String>();
        Test.startTest();
        System.runAs(rep)
        {
            for (String soql : new List<String>{
                'SELECT Id, Forge_Test_Secret__c FROM Opportunity WHERE OwnerId = :ownerId',
                'SELECT Id FROM Opportunity WHERE OwnerId = :ownerId AND Forge_Test_Secret__c = null'
            })
            {
                try
                {
                    ForgeAccess.query(soql, ownedBy(rep));
                    Assert.fail('The rep may not read Forge_Test_Secret__c: ' + soql);
                }
                catch (ForgeAccess.AccessDeniedException denied)
                {
                    messages.add(denied.getMessage());
                    Assert.areEqual('Opportunity', denied.objectName);
                    Assert.areEqual('Forge_Test_Secret__c', denied.fieldName);
                    Assert.areEqual(ForgeAccess.Access.READ, denied.access);
                }
            }
        }
        Test.stopTest();
        Assert.areEqual(new List<String>{ 'You cannot read Opportunity.Forge_Test_Secret__c.', 'You cannot read Opportunity.Forge_Test_Secret__c.' }, messages);
    }

    @IsTest
    static void severalUnreadableFieldsAreNamedFirstAndCounted()
    {
        User outsider = anOutsider();
        opportunitiesOwnedBy(outsider, 1);
        ForgeAccess.AccessDeniedException denied;
        Test.startTest();
        System.runAs(outsider)
        {
            try
            {
                ForgeAccess.query('SELECT Id, Forge_Test_Secret__c, Forge_Test_Notes__c FROM Opportunity WHERE OwnerId = :ownerId', ownedBy(outsider));
            }
            catch (ForgeAccess.AccessDeniedException failure)
            {
                denied = failure;
            }
        }
        Test.stopTest();
        Assert.areEqual('You cannot read Opportunity.Forge_Test_Notes__c and 1 more field.', denied.getMessage());
        Assert.areEqual(new List<String>{ 'Opportunity.Forge_Test_Notes__c', 'Opportunity.Forge_Test_Secret__c' }, denied.deniedFields);
    }

    @IsTest
    static void anObjectClosedToTheUserRefusesEveryKindOfAccess()
    {
        User owner = aSalesRep();
        User outsider = anOutsider();
        Opportunity opportunity = opportunitiesOwnedBy(owner, 1)[0];
        Forge_Test_Line__c line = aLineOn(opportunity);
        List<String> messages = new List<String>();
        Test.startTest();
        System.runAs(outsider)
        {
            try { ForgeAccess.query('SELECT Id FROM Forge_Test_Line__c', new Map<String, Object>()); }
            catch (ForgeAccess.AccessDeniedException denied) { messages.add(denied.getMessage()); }
            try { ForgeAccess.query('SELECT Id, Opportunity__r.Name FROM Forge_Test_Line__c', new Map<String, Object>()); }
            catch (ForgeAccess.AccessDeniedException denied) { messages.add(denied.getMessage()); }
            try { ForgeAccess.save(new List<Forge_Test_Line__c>{ new Forge_Test_Line__c(Name = 'New', Opportunity__c = opportunity.Id) }); }
            catch (ForgeAccess.AccessDeniedException denied) { messages.add(denied.getMessage()); }
            try { ForgeAccess.save(new List<Forge_Test_Line__c>{ new Forge_Test_Line__c(Id = line.Id, Hours__c = 2) }); }
            catch (ForgeAccess.AccessDeniedException denied) { messages.add(denied.getMessage()); }
        }
        Test.stopTest();
        Assert.areEqual(
            new List<String>{
                'You cannot read Forge_Test_Line__c.',
                'You cannot read Forge_Test_Line__c.',
                'You cannot create Forge_Test_Line__c.',
                'You cannot edit Forge_Test_Line__c.'
            },
            messages
        );
        Assert.areEqual(1, [SELECT COUNT() FROM Forge_Test_Line__c]);
        Assert.areEqual(1, [SELECT Hours__c FROM Forge_Test_Line__c WHERE Id = :line.Id].Hours__c);
    }

    @IsTest
    static void anObjectTheRepMayNotDeleteIsNotRemoved()
    {
        User rep = aSalesRep();
        Forge_Test_Line__c line = aLineOn(opportunitiesOwnedBy(rep, 1)[0]);
        ForgeAccess.AccessDeniedException denied;
        Test.startTest();
        System.runAs(rep)
        {
            try { ForgeAccess.remove(new List<Forge_Test_Line__c>{ line }); }
            catch (ForgeAccess.AccessDeniedException failure) { denied = failure; }
        }
        Test.stopTest();
        Assert.areEqual('You cannot delete Forge_Test_Line__c.', denied.getMessage());
        Assert.areEqual(ForgeAccess.Access.REMOVE, denied.access);
        Assert.isNull(denied.fieldName);
        Assert.areEqual(1, [SELECT COUNT() FROM Forge_Test_Line__c WHERE Id = :line.Id]);
    }

    @IsTest
    static void aFieldTheRepMayOnlyReadRefusesTheSaveAndSavesNothing()
    {
        User rep = aSalesRep();
        Opportunity opportunity = opportunitiesOwnedBy(rep, 1)[0];
        ForgeAccess.AccessDeniedException denied;
        Test.startTest();
        System.runAs(rep)
        {
            try
            {
                ForgeAccess.save(new List<Opportunity>{
                    new Opportunity(Id = opportunity.Id, Forge_Test_Margin__c = 9, Forge_Test_Notes__c = 'Second call')
                });
            }
            catch (ForgeAccess.AccessDeniedException failure)
            {
                denied = failure;
            }
        }
        Test.stopTest();
        Assert.areEqual('You cannot edit Opportunity.Forge_Test_Margin__c.', denied.getMessage());
        Assert.areEqual(ForgeAccess.Access.EDIT, denied.access);
        Opportunity stored = [SELECT Forge_Test_Margin__c, Forge_Test_Notes__c FROM Opportunity WHERE Id = :opportunity.Id];
        Assert.areEqual(5, stored.Forge_Test_Margin__c);
        Assert.areEqual('First call', stored.Forge_Test_Notes__c);
    }

    @IsTest
    static void aFieldTheRepMayNotSetOnANewRecordRefusesTheInsertAndAddsNothing()
    {
        User rep = aSalesRep();
        Opportunity added = new Opportunity(Name = 'Added', StageName = 'Prospecting', CloseDate = Date.today(), Forge_Test_Margin__c = 9);
        ForgeAccess.AccessDeniedException denied;
        Test.startTest();
        System.runAs(rep)
        {
            try
            {
                ForgeAccess.save(new List<Opportunity>{ added });
            }
            catch (ForgeAccess.AccessDeniedException failure)
            {
                denied = failure;
            }
        }
        Test.stopTest();
        Assert.areEqual('You cannot create Opportunity.Forge_Test_Margin__c.', denied.getMessage());
        Assert.areEqual(ForgeAccess.Access.CREATE, denied.access);
        Assert.areEqual('Forge_Test_Margin__c', denied.fieldName);
        Assert.isNull(added.Id);
        Assert.areEqual(0, [SELECT COUNT() FROM Opportunity WHERE Name = 'Added']);
    }

    @IsTest
    static void severalFieldsTheUserMayNotEditAreNamedFirstAndCounted()
    {
        User outsider = anOutsider();
        Opportunity opportunity = opportunitiesOwnedBy(outsider, 1)[0];
        String message;
        Test.startTest();
        System.runAs(outsider)
        {
            try
            {
                ForgeAccess.save(new List<Opportunity>{
                    new Opportunity(Id = opportunity.Id, Forge_Test_Notes__c = 'Second call', Forge_Test_Margin__c = 9)
                });
            }
            catch (ForgeAccess.AccessDeniedException denied)
            {
                message = denied.getMessage();
            }
        }
        Test.stopTest();
        Assert.areEqual('You cannot edit Opportunity.Forge_Test_Margin__c and 1 more field.', message);
    }

    @IsTest
    static void leavingOutUneditableSavesTheRestAndSaysWhatWasLeftOut()
    {
        User rep = aSalesRep();
        opportunitiesOwnedBy(rep, 200);
        Set<String> leftOut;
        Test.startTest();
        System.runAs(rep)
        {
            List<Opportunity> changes = new List<Opportunity>();
            for (Opportunity opportunity : [SELECT Id FROM Opportunity WHERE OwnerId = :rep.Id])
            {
                changes.add(new Opportunity(Id = opportunity.Id, Forge_Test_Margin__c = 9, Forge_Test_Notes__c = 'Second call'));
            }
            ForgeAccess.leavingOutUneditable().save(changes);
            leftOut = ForgeAccess.lastLeftOut();
        }
        Test.stopTest();
        Assert.areEqual(new Set<String>{ 'Opportunity.Forge_Test_Margin__c' }, leftOut);
        for (Opportunity stored : [SELECT Forge_Test_Margin__c, Forge_Test_Notes__c FROM Opportunity WHERE OwnerId = :rep.Id])
        {
            Assert.areEqual(5, stored.Forge_Test_Margin__c);
            Assert.areEqual('Second call', stored.Forge_Test_Notes__c);
        }
    }

    @IsTest
    static void aQueriedRecordSavesWithItsReadOnlyAndSalesforceMaintainedFieldsUnchanged()
    {
        User rep = aSalesRep();
        List<Opportunity> owned = opportunitiesOwnedBy(rep, 200);
        aLineOn(owned[0]);
        Test.startTest();
        System.runAs(rep)
        {
            List<Opportunity> opportunities = (List<Opportunity>) ForgeAccess.query(
                'SELECT Id, Name, StageName, CreatedDate, LastModifiedById, Forge_Test_Margin__c, Forge_Test_Doubled_Margin__c,'
                    + ' Forge_Test_Line_Count__c, Forge_Test_Number__c, Forge_Test_Notes__c FROM Opportunity WHERE OwnerId = :ownerId',
                ownedBy(rep)
            );
            for (Opportunity opportunity : opportunities) { opportunity.Forge_Test_Notes__c = 'Second call'; }
            ForgeAccess.save(opportunities);
            Assert.isTrue(ForgeAccess.lastLeftOut().isEmpty());
        }
        Test.stopTest();
        Assert.areEqual(200, [SELECT COUNT() FROM Opportunity WHERE OwnerId = :rep.Id AND Forge_Test_Notes__c = 'Second call']);
    }

    @IsTest
    static void formulaRollUpAutoNumberAndAuditFieldsSentFromAComponentAreNeitherWrittenNorRefused()
    {
        User rep = aSalesRep();
        Opportunity opportunity = opportunitiesOwnedBy(rep, 1)[0];
        aLineOn(opportunity);
        Opportunity stored = [
            SELECT Id, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, SystemModstamp,
                Forge_Test_Doubled_Margin__c, Forge_Test_Line_Count__c, Forge_Test_Number__c
            FROM Opportunity WHERE Id = :opportunity.Id
        ];
        Map<String, Object> sent = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(stored));
        sent.put('Forge_Test_Doubled_Margin__c', 1000);
        sent.put('Forge_Test_Line_Count__c', 7);
        sent.put('Forge_Test_Number__c', 'FT-9999');
        sent.put('StageName', 'Qualification');
        Opportunity fromComponent = (Opportunity) JSON.deserialize(JSON.serialize(sent), Opportunity.class);
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.save(new List<Opportunity>{ fromComponent });
        }
        Test.stopTest();
        Opportunity saved = [
            SELECT StageName, CreatedDate, Forge_Test_Doubled_Margin__c, Forge_Test_Line_Count__c, Forge_Test_Number__c
            FROM Opportunity WHERE Id = :opportunity.Id
        ];
        Assert.areEqual('Qualification', saved.StageName, 'A required field a permission set cannot change is written.');
        Assert.areEqual(10, saved.Forge_Test_Doubled_Margin__c);
        Assert.areEqual(1, saved.Forge_Test_Line_Count__c);
        Assert.areEqual(stored.Forge_Test_Number__c, saved.Forge_Test_Number__c);
        Assert.areEqual(stored.CreatedDate, saved.CreatedDate);
    }

    @IsTest
    static void aFieldWritableOnCreateIsRefusedOnUpdate()
    {
        User rep = aSalesRep();
        List<Opportunity> opportunities = opportunitiesOwnedBy(rep, 2);
        Forge_Test_Line__c line = new Forge_Test_Line__c(Name = 'Line', Opportunity__c = opportunities[0].Id, Hours__c = 1);
        String message;
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.save(new List<Forge_Test_Line__c>{ line });
            try
            {
                Map<String, Object> moved = new Map<String, Object>{ 'Id' => line.Id, 'Opportunity__c' => opportunities[1].Id };
                Forge_Test_Line__c fromComponent = (Forge_Test_Line__c) JSON.deserialize(JSON.serialize(moved), Forge_Test_Line__c.class);
                ForgeAccess.save(new List<Forge_Test_Line__c>{ fromComponent });
            }
            catch (ForgeAccess.AccessDeniedException denied)
            {
                message = denied.getMessage();
            }
        }
        Test.stopTest();
        Assert.isNotNull(line.Id);
        Assert.areEqual('You cannot edit Forge_Test_Line__c.Opportunity__c.', message);
        Assert.areEqual(opportunities[0].Id, [SELECT Opportunity__c FROM Forge_Test_Line__c WHERE Id = :line.Id].Opportunity__c);
    }

    @IsTest
    static void fieldsNobodyMayWriteSentBackFromAComponentRefuseTheSave()
    {
        User rep = aSalesRep();
        Opportunity opportunity = opportunitiesOwnedBy(rep, 1)[0];
        Opportunity fromComponent = sentBackWhole(opportunity);
        ForgeAccess.AccessDeniedException denied;
        Test.startTest();
        System.runAs(rep)
        {
            try
            {
                ForgeAccess.save(new List<Opportunity>{ fromComponent });
            }
            catch (ForgeAccess.AccessDeniedException refused)
            {
                denied = refused;
            }
        }
        Test.stopTest();
        Assert.areEqual('You cannot edit Opportunity.ExpectedRevenue and 1 more field.', denied.getMessage());
        Assert.areEqual(new List<String>{ 'Opportunity.ExpectedRevenue', 'Opportunity.IsClosed' }, denied.deniedFields);
        Assert.areEqual('Prospecting', [SELECT StageName FROM Opportunity WHERE Id = :opportunity.Id].StageName);
    }

    @IsTest
    static void fieldsNobodyMayWriteAreLeftOutWhenAsked()
    {
        User rep = aSalesRep();
        Opportunity opportunity = opportunitiesOwnedBy(rep, 1)[0];
        Opportunity fromComponent = sentBackWhole(opportunity);
        Set<String> leftOut;
        Test.startTest();
        System.runAs(rep)
        {
            ForgeAccess.leavingOutUneditable().save(new List<Opportunity>{ fromComponent });
            leftOut = ForgeAccess.lastLeftOut();
        }
        Test.stopTest();
        Assert.areEqual(new Set<String>{ 'Opportunity.ExpectedRevenue', 'Opportunity.IsClosed' }, leftOut);
        Assert.areEqual('Qualification', [SELECT StageName FROM Opportunity WHERE Id = :opportunity.Id].StageName);
    }
}
