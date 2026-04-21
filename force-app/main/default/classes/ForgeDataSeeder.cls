/**
 * This file is part of the Forge Platform project
 *
 * Seed-value helper for tests: UK-flavored names, addresses, phone numbers,
 * postcodes, and companies; plus lorem text and range-bounded primitives.
 * Also provides ForgeDataBuilder.ValueProvider implementations (sequence, firstNames,
 * lastNames, emails) for per-record variation under .count(n).
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class ForgeDataSeeder {

    private static final List<String> FIRST_NAMES = new List<String>{
        'Agatha','Alfie','Archie','Arthur','Beatrice','Beatrix','Bertie','Cedric',
        'Charlie','Clive','Cyril','Dorothy','Edith','Eleanor','Ethel','Florence',
        'Freddie','George','Harriet','Henry','Hugo','Imogen','Isla','Jasper',
        'Jewelyn','Lewis','Margot','Millie','Nigel','Oliver','Oscar','Percy',
        'Poppy','Rupert','Sebastian','Tabitha','Teddy','Theo','Tony','Violet',
        'Wilfred','Winifred'
    };

    private static final List<String> LAST_NAMES = new List<String>{
        'Abbott','Ashby','Ashworth','Barnaby','Bennett','Blackwood','Brookes',
        'Carlisle','Chopper','Churchill','Crawford','Cromwell','Fairchild',
        'Fitzwilliam','Hadley','Hargreaves','Harrington','Holloway','Kensington',
        'Kingsley','Lancaster','Marston','Montgomery','Pemberton','Pendleton',
        'Pickering','Radcliffe','Ravenscroft','Stanton','Sutcliffe','Thornbury',
        'Thornton','Wellington','Whitaker','Winterbourne','Worthington'
    };

    private static final List<String> COMPANY_PREFIXES = new List<String>{
        'Albion','Ascot','Ashcroft','Britannia','Camden','Cavendish','Chelsea',
        'Cotswold','Dartmoor','Hampton','Kensington','Oakworth','Pembroke',
        'Regent','Thames','Tudor','Westminster','Wessex','Yorkshire'
    };

    private static final List<String> COMPANY_SUFFIXES = new List<String>{
        'Ltd','PLC','Holdings','Group','Partners','& Sons','& Co','Brothers',
        'Trading','Enterprises'
    };

    private static final List<String> CITIES = new List<String>{
        'Bath','Brighton','Bristol','Cambridge','Canterbury','Chester','Coventry',
        'Durham','Exeter','Harrogate','Lancaster','Leeds','Liverpool','Manchester',
        'Newcastle','Norwich','Nottingham','Oxford','Plymouth','Portsmouth',
        'Reading','Sheffield','Southampton','Winchester','York'
    };

    private static final List<String> STREETS = new List<String>{
        'Albion','Ashcroft','Baker','Bishopsgate','Cavendish','Downing',
        'Kensington','Knightsbridge','Marylebone','Montague','Oxford','Paddington',
        'Piccadilly','Portobello','Regent','Shaftesbury','Strand','Victoria',
        'Westminster'
    };

    private static final List<String> STREET_SUFFIXES = new List<String>{
        'St','Rd','Ln','Mews','Crescent','Gardens','Terrace','Close','Row',
        'Square','Place','Court','Avenue','Hill','Walk'
    };

    private static final List<String> POSTCODE_AREAS = new List<String>{
        'SW','NW','SE','NE','EC','WC','BA','BN','BR','BS','CA','CB','CV','DH',
        'EX','GL','HR','KA','LN','LS','MK','NR','OX','PO','SL','ST','YO'
    };

    private static final List<String> ALPHA = new List<String>{
        'A','B','C','D','E','F','G','H','J','K','L','M','N','P','Q','R','S','T',
        'U','V','W','X','Y','Z'
    };

    private static final List<String> LOREM = new List<String>{
        'lorem','ipsum','dolor','sit','amet','consectetur','adipiscing','elit',
        'sed','do','eiusmod','tempor','incididunt','ut','labore','et','dolore',
        'magna','aliqua','veniam','quis','nostrud','exercitation','ullamco'
    };

    public static String firstName() { return pickString(FIRST_NAMES); }

    public static String lastName() { return pickString(LAST_NAMES); }

    public static String fullName() { return firstName() + ' ' + lastName(); }

    public static String email() { return email(firstName(), lastName()); }

    public static String email(String first, String last)
    {
        return first.toLowerCase() + '.' + last.toLowerCase()
            + '+' + integerBetween(1000, 9999) + '@example.co.uk';
    }

    public static String company()
    {
        return pickString(COMPANY_PREFIXES) + ' ' + pickString(COMPANY_SUFFIXES);
    }

    public static String phone()
    {
        return '07' + integerBetween(100, 999)
            + ' ' + integerBetween(100000, 999999);
    }

    public static String streetAddress()
    {
        return integerBetween(1, 9999) + ' '
            + pickString(STREETS) + ' ' + pickString(STREET_SUFFIXES);
    }

    public static String city() { return pickString(CITIES); }

    public static String postalCode()
    {
        return pickString(POSTCODE_AREAS) + integerBetween(1, 20)
            + ' ' + integerBetween(1, 9) + pickString(ALPHA) + pickString(ALPHA);
    }

    public static String word() { return pickString(LOREM); }

    public static String sentence(Integer words)
    {
        if (words == null || words < 1) { words = 1; }
        List<String> parts = new List<String>();
        for (Integer i = 0; i < words; i++) { parts.add(word()); }
        String s = String.join(parts, ' ');
        return s.substring(0, 1).toUpperCase() + s.substring(1) + '.';
    }

    public static String paragraph(Integer sentences)
    {
        if (sentences == null || sentences < 1) { sentences = 1; }
        List<String> parts = new List<String>();
        for (Integer i = 0; i < sentences; i++) {
            parts.add(sentence(integerBetween(5, 12)));
        }
        return String.join(parts, ' ');
    }

    public static Integer integerBetween(Integer lo, Integer hi)
    {
        if (lo > hi) { Integer t = lo; lo = hi; hi = t; }
        return lo + (Integer) (Math.random() * (hi - lo + 1));
    }

    public static Decimal decimalBetween(Decimal lo, Decimal hi, Integer scale)
    {
        if (lo > hi) { Decimal t = lo; lo = hi; hi = t; }
        Decimal v = lo + (hi - lo) * Decimal.valueOf(Math.random());
        return v.setScale(scale);
    }

    public static Date dateBetween(Date lo, Date hi)
    {
        Integer days = lo.daysBetween(hi);
        if (days < 0) { Date t = lo; lo = hi; hi = t; days = -days; }
        return lo.addDays(integerBetween(0, days));
    }

    public static Datetime datetimeBetween(Datetime lo, Datetime hi)
    {
        Long loMs = lo.getTime();
        Long hiMs = hi.getTime();
        if (loMs > hiMs) { Long t = loMs; loMs = hiMs; hiMs = t; }
        Long offset = (Long) ((hiMs - loMs) * Math.random());
        return Datetime.newInstance(loMs + offset);
    }

    public static Boolean coinFlip() { return Math.random() < 0.5; }

    public static Object pickFrom(List<Object> choices)
    {
        if (choices == null || choices.isEmpty()) { return null; }
        return choices[integerBetween(0, choices.size() - 1)];
    }

    public static ForgeDataBuilder.ValueProvider sequence(String prefix)
    {
        return new SequenceProvider(prefix);
    }

    public static ForgeDataBuilder.ValueProvider firstNames()
    {
        return new CycleProvider(FIRST_NAMES);
    }

    public static ForgeDataBuilder.ValueProvider lastNames()
    {
        return new CycleProvider(LAST_NAMES);
    }

    public static ForgeDataBuilder.ValueProvider emails()
    {
        return new EmailProvider();
    }

    private static String pickString(List<String> choices)
    {
        if (choices == null || choices.isEmpty()) { return null; }
        return choices[integerBetween(0, choices.size() - 1)];
    }

    private class SequenceProvider implements ForgeDataBuilder.ValueProvider {
        private final String prefix;
        public SequenceProvider(String p) { this.prefix = p; }
        public Object get(Integer i) { return prefix + ' ' + (i + 1); }
    }

    private class CycleProvider implements ForgeDataBuilder.ValueProvider {
        private final List<String> source;
        public CycleProvider(List<String> s) { this.source = s; }
        public Object get(Integer i) {
            return source[Math.mod(i, source.size())];
        }
    }

    private class EmailProvider implements ForgeDataBuilder.ValueProvider {
        public Object get(Integer i) {
            return 'user' + (i + 1) + '+' + integerBetween(1000, 9999) + '@example.co.uk';
        }
    }
}
