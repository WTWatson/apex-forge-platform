@IsTest
private class ForgeDataSeederTest {

    @IsTest
    static void scalarsAreNonEmpty()
    {
        Assert.isNotNull(ForgeDataSeeder.firstName());
        Assert.isTrue(ForgeDataSeeder.firstName().length() > 0);
        Assert.isNotNull(ForgeDataSeeder.lastName());
        Assert.isTrue(ForgeDataSeeder.lastName().length() > 0);
        Assert.isTrue(ForgeDataSeeder.fullName().contains(' '));
        Assert.isTrue(ForgeDataSeeder.email().contains('@'));
        Assert.isTrue(ForgeDataSeeder.company().length() > 0);
        Assert.isTrue(ForgeDataSeeder.phone().length() > 0);
        Assert.isTrue(ForgeDataSeeder.city().length() > 0);
        Assert.isTrue(ForgeDataSeeder.streetAddress().length() > 0);
        Assert.isTrue(ForgeDataSeeder.word().length() > 0);
    }

    @IsTest
    static void postcodeLooksUkShaped()
    {
        String pc = ForgeDataSeeder.postalCode();

        Assert.isTrue(pc.length() >= 6 && pc.length() <= 8,
            'UK postcode should be 6-8 characters');
        Assert.isTrue(pc.contains(' '), 'UK postcode should contain a space');
    }

    @IsTest
    static void emailWithNamesIsWellFormed()
    {
        String e = ForgeDataSeeder.email('Alex', 'Smith');

        Assert.isTrue(e.startsWith('alex.smith+'));
        Assert.isTrue(e.endsWith('@example.co.uk'));
    }

    @IsTest
    static void sentenceStartsCapitalAndEndsPeriod()
    {
        String s = ForgeDataSeeder.sentence(4);

        Assert.areEqual(s.substring(0, 1), s.substring(0, 1).toUpperCase(),
            'Sentence should start with a capital letter');
        Assert.isTrue(s.endsWith('.'), 'Sentence should end with a period');
    }

    @IsTest
    static void paragraphHasOneSentencePerRequest()
    {
        String p = ForgeDataSeeder.paragraph(3);

        Assert.areEqual(3, p.countMatches('.'),
            'Paragraph should contain one period per requested sentence');
    }

    @IsTest
    static void integerBetweenRespectsBounds()
    {
        for (Integer i = 0; i < 50; i++) {
            Integer v = ForgeDataSeeder.integerBetween(10, 20);
            Assert.isTrue(v >= 10 && v <= 20);
        }
    }

    @IsTest
    static void integerBetweenHandlesSwappedBounds()
    {
        Integer v = ForgeDataSeeder.integerBetween(20, 10);

        Assert.isTrue(v >= 10 && v <= 20,
            'Swapped bounds should still produce an in-range value');
    }

    @IsTest
    static void decimalBetweenRespectsScale()
    {
        Decimal v = ForgeDataSeeder.decimalBetween(0, 1, 2);

        Assert.areEqual(2, v.scale());
        Assert.isTrue(v >= 0 && v <= 1);
    }

    @IsTest
    static void dateBetweenRespectsBounds()
    {
        Date lo = Date.newInstance(2026, 1, 1);
        Date hi = Date.newInstance(2026, 12, 31);

        Date d = ForgeDataSeeder.dateBetween(lo, hi);

        Assert.isTrue(d >= lo && d <= hi);
    }

    @IsTest
    static void dateBetweenHandlesSwappedBounds()
    {
        Date lo = Date.newInstance(2026, 12, 31);
        Date hi = Date.newInstance(2026, 1, 1);

        Date d = ForgeDataSeeder.dateBetween(lo, hi);

        Assert.isTrue(d >= hi && d <= lo);
    }

    @IsTest
    static void datetimeBetweenRespectsBounds()
    {
        Datetime lo = Datetime.newInstance(2026, 1, 1, 0, 0, 0);
        Datetime hi = Datetime.newInstance(2026, 12, 31, 23, 59, 59);

        Datetime d = ForgeDataSeeder.datetimeBetween(lo, hi);

        Assert.isTrue(d >= lo && d <= hi);
    }

    @IsTest
    static void sequenceProviderEmitsIndexedValues()
    {
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.sequence('X');

        Assert.areEqual('X 1', p.get(0));
        Assert.areEqual('X 2', p.get(1));
        Assert.areEqual('X 10', p.get(9));
    }

    @IsTest
    static void firstNamesProviderYieldsDifferentConsecutiveValues()
    {
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.firstNames();

        String a0 = (String) p.get(0);
        String a1 = (String) p.get(1);

        Assert.isNotNull(a0);
        Assert.isNotNull(a1);
        Assert.areNotEqual(a0, a1,
            'Consecutive indices should yield different names');
    }

    @IsTest
    static void lastNamesProviderYieldsDifferentConsecutiveValues()
    {
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.lastNames();

        String a0 = (String) p.get(0);
        String a1 = (String) p.get(1);

        Assert.areNotEqual(a0, a1);
    }

    @IsTest
    static void emailsProviderYieldsUniqueAddresses()
    {
        ForgeDataBuilder.ValueProvider p = ForgeDataSeeder.emails();

        Set<String> seen = new Set<String>();
        for (Integer i = 0; i < 5; i++) {
            seen.add((String) p.get(i));
        }

        Assert.areEqual(5, seen.size(),
            'Emails provider should yield unique values across indices');
    }

    @IsTest
    static void pickFromReturnsMember()
    {
        List<Object> choices = new List<Object>{ 'a', 'b', 'c' };

        Object picked = ForgeDataSeeder.pickFrom(choices);

        Assert.isTrue(new Set<Object>(choices).contains(picked));
    }

    @IsTest
    static void pickFromEmptyReturnsNull()
    {
        Assert.isNull(ForgeDataSeeder.pickFrom(new List<Object>()));
        Assert.isNull(ForgeDataSeeder.pickFrom(null));
    }

    @IsTest
    static void coinFlipReturnsBoolean()
    {
        Assert.isNotNull(ForgeDataSeeder.coinFlip());
    }

    @IsTest
    static void sentenceHandlesZeroOrNegative()
    {
        Assert.isTrue(ForgeDataSeeder.sentence(0).endsWith('.'));
        Assert.isTrue(ForgeDataSeeder.sentence(null).endsWith('.'));
    }

    @IsTest
    static void paragraphHandlesZeroOrNegative()
    {
        Assert.isTrue(ForgeDataSeeder.paragraph(0).endsWith('.'));
    }
}
