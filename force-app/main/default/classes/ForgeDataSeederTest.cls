@IsTest
private class ForgeDataSeederTest {

    @IsTest
    static void scalarsAreNonEmpty()
    {
        Test.startTest();
        String firstName = ForgeDataSeeder.firstName();
        String lastName = ForgeDataSeeder.lastName();
        String fullName = ForgeDataSeeder.fullName();
        String email = ForgeDataSeeder.email();
        String company = ForgeDataSeeder.company();
        String phone = ForgeDataSeeder.phone();
        String city = ForgeDataSeeder.city();
        String streetAddress = ForgeDataSeeder.streetAddress();
        String word = ForgeDataSeeder.word();
        Test.stopTest();

        Assert.isNotNull(firstName);
        Assert.isTrue(firstName.length() > 0);
        Assert.isNotNull(lastName);
        Assert.isTrue(lastName.length() > 0);
        Assert.isTrue(fullName.contains(' '));
        Assert.isTrue(email.contains('@'));
        Assert.isTrue(company.length() > 0);
        Assert.isTrue(phone.length() > 0);
        Assert.isTrue(city.length() > 0);
        Assert.isTrue(streetAddress.length() > 0);
        Assert.isTrue(word.length() > 0);
    }

    @IsTest
    static void postcodeLooksUkShaped()
    {
        Test.startTest();
        String pc = ForgeDataSeeder.postalCode();
        Test.stopTest();

        Assert.isTrue(pc.length() >= 6 && pc.length() <= 8,
            'UK postcode should be 6-8 characters');
        Assert.isTrue(pc.contains(' '), 'UK postcode should contain a space');
    }

    @IsTest
    static void emailWithNamesIsWellFormed()
    {
        Test.startTest();
        String e = ForgeDataSeeder.email('Alex', 'Smith');
        Test.stopTest();

        Assert.isTrue(e.startsWith('alex.smith+'));
        Assert.isTrue(e.endsWith('@example.co.uk'));
    }

    @IsTest
    static void sentenceStartsCapitalAndEndsPeriod()
    {
        Test.startTest();
        String s = ForgeDataSeeder.sentence(4);
        Test.stopTest();

        Assert.areEqual(s.substring(0, 1), s.substring(0, 1).toUpperCase(),
            'Sentence should start with a capital letter');
        Assert.isTrue(s.endsWith('.'), 'Sentence should end with a period');
    }

    @IsTest
    static void paragraphHasOneSentencePerRequest()
    {
        Test.startTest();
        String p = ForgeDataSeeder.paragraph(3);
        Test.stopTest();

        Assert.areEqual(3, p.countMatches('.'),
            'Paragraph should contain one period per requested sentence');
    }

    @IsTest
    static void integerBetweenRespectsBounds()
    {
        List<Integer> values = new List<Integer>();
        Test.startTest();
        for (Integer i = 0; i < 50; i++) {
            values.add(ForgeDataSeeder.integerBetween(10, 20));
        }
        Test.stopTest();

        for (Integer v : values) {
            Assert.isTrue(v >= 10 && v <= 20);
        }
    }

    @IsTest
    static void integerBetweenHandlesSwappedBounds()
    {
        Test.startTest();
        Integer v = ForgeDataSeeder.integerBetween(20, 10);
        Test.stopTest();

        Assert.isTrue(v >= 10 && v <= 20,
            'Swapped bounds should still produce an in-range value');
    }

    @IsTest
    static void decimalBetweenRespectsScale()
    {
        Test.startTest();
        Decimal v = ForgeDataSeeder.decimalBetween(0, 1, 2);
        Test.stopTest();

        Assert.areEqual(2, v.scale());
        Assert.isTrue(v >= 0 && v <= 1);
    }

    @IsTest
    static void dateBetweenRespectsBounds()
    {
        Date earliest = Date.newInstance(2026, 1, 1);
        Date latest = Date.newInstance(2026, 12, 31);

        Test.startTest();
        Date d = ForgeDataSeeder.dateBetween(earliest, latest);
        Test.stopTest();

        Assert.isTrue(d >= earliest && d <= latest);
    }

    @IsTest
    static void dateBetweenHandlesSwappedBounds()
    {
        Date latest = Date.newInstance(2026, 12, 31);
        Date earliest = Date.newInstance(2026, 1, 1);

        Test.startTest();
        Date d = ForgeDataSeeder.dateBetween(latest, earliest);
        Test.stopTest();

        Assert.isTrue(d >= earliest && d <= latest);
    }

    @IsTest
    static void datetimeBetweenRespectsBounds()
    {
        Datetime earliest = Datetime.newInstance(2026, 1, 1, 0, 0, 0);
        Datetime latest = Datetime.newInstance(2026, 12, 31, 23, 59, 59);

        Test.startTest();
        Datetime d = ForgeDataSeeder.datetimeBetween(earliest, latest);
        Test.stopTest();

        Assert.isTrue(d >= earliest && d <= latest);
    }

    @IsTest
    static void sequenceProviderEmitsIndexedValues()
    {
        Test.startTest();
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.sequence('X');
        Object first = p.get(0);
        Object second = p.get(1);
        Object tenth = p.get(9);
        Test.stopTest();

        Assert.areEqual('X 1', first);
        Assert.areEqual('X 2', second);
        Assert.areEqual('X 10', tenth);
    }

    @IsTest
    static void sequenceProviderNumbers200ValuesApart()
    {
        List<Object> values = new List<Object>();
        Test.startTest();
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.sequence('X');
        for (Integer index = 0; index < 200; index++) {
            values.add(p.get(index));
        }
        Test.stopTest();

        Assert.areEqual(200, new Set<Object>(values).size());
        Assert.areEqual('X 1', values[0]);
        Assert.areEqual('X 200', values[199]);
    }

    @IsTest
    static void firstNamesProviderYieldsDifferentConsecutiveValues()
    {
        Test.startTest();
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.firstNames();
        String a0 = (String) p.get(0);
        String a1 = (String) p.get(1);
        Test.stopTest();

        Assert.isNotNull(a0);
        Assert.isNotNull(a1);
        Assert.areNotEqual(a0, a1,
            'Consecutive indices should yield different names');
    }

    @IsTest
    static void firstNamesProviderRepeatsTheListAcross200Values()
    {
        List<String> values = new List<String>();
        Test.startTest();
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.firstNames();
        for (Integer index = 0; index < 200; index++) {
            values.add((String) p.get(index));
        }
        Test.stopTest();

        Integer namesInList = new Set<String>(values).size();
        Assert.isTrue(namesInList > 1 && namesInList < 200, 'The names should repeat once the list runs out');
        for (Integer index = 0; index < 200; index++) {
            Assert.isNotNull(values[index]);
            Assert.areEqual(values[Math.mod(index, namesInList)], values[index],
                'The list should start again from the first name when it runs out');
        }
    }

    @IsTest
    static void lastNamesProviderYieldsDifferentConsecutiveValues()
    {
        Test.startTest();
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.lastNames();
        String a0 = (String) p.get(0);
        String a1 = (String) p.get(1);
        Test.stopTest();

        Assert.areNotEqual(a0, a1);
    }

    @IsTest
    static void emailsProviderYieldsUniqueAddresses()
    {
        Set<String> seen = new Set<String>();
        Test.startTest();
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.emails();
        for (Integer i = 0; i < 5; i++) {
            seen.add((String) p.get(i));
        }
        Test.stopTest();

        Assert.areEqual(5, seen.size(),
            'Emails provider should yield unique values across indices');
    }

    @IsTest
    static void emailsProviderYields200UniqueAddresses()
    {
        Set<String> seen = new Set<String>();
        Test.startTest();
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.emails();
        for (Integer index = 0; index < 200; index++) {
            seen.add((String) p.get(index));
        }
        Test.stopTest();

        Assert.areEqual(200, seen.size(),
            'Emails provider should yield unique values across 200 indices');
        for (String address : seen) {
            Assert.isTrue(address.endsWith('@example.co.uk'));
        }
    }

    @IsTest
    static void pickFromReturnsMember()
    {
        List<Object> choices = new List<Object>{ 'a', 'b', 'c' };

        Test.startTest();
        Object picked = ForgeDataSeeder.pickFrom(choices);
        Test.stopTest();

        Assert.isTrue(new Set<Object>(choices).contains(picked));
    }

    @IsTest
    static void pickFromEmptyReturnsNull()
    {
        Test.startTest();
        Object fromEmpty = ForgeDataSeeder.pickFrom(new List<Object>());
        Object fromNull = ForgeDataSeeder.pickFrom(null);
        Test.stopTest();

        Assert.isNull(fromEmpty);
        Assert.isNull(fromNull);
    }

    @IsTest
    static void coinFlipReturnsBoolean()
    {
        Test.startTest();
        Boolean flipped = ForgeDataSeeder.coinFlip();
        Test.stopTest();

        Assert.isNotNull(flipped);
    }

    @IsTest
    static void sentenceHandlesZeroOrNegative()
    {
        Test.startTest();
        String fromZero = ForgeDataSeeder.sentence(0);
        String fromNull = ForgeDataSeeder.sentence(null);
        Test.stopTest();

        Assert.isTrue(fromZero.endsWith('.'));
        Assert.isTrue(fromNull.endsWith('.'));
    }

    @IsTest
    static void paragraphHandlesZeroOrNegative()
    {
        Test.startTest();
        String fromZero = ForgeDataSeeder.paragraph(0);
        Test.stopTest();

        Assert.isTrue(fromZero.endsWith('.'));
    }
}
