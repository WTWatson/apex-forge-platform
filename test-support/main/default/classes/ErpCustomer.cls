/**
 * This file is part of the Forge Platform project
 *
 * Test support only: the customer as the ERP in the ForgeHttp scenario receives it.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
/** A customer as the ERP receives it. */
public with sharing class ErpCustomer
{
    /** The Account's Salesforce Id, by which the ERP recognises a customer it already has. */
    public String salesforceId;

    /** The customer's name. */
    public String name;

    /** The ERP customers for these Accounts, in the same order. */
    public static List<ErpCustomer> fromAccounts(List<Account> accounts)
    {
        List<ErpCustomer> customers = new List<ErpCustomer>();
        for (Account account : accounts)
        {
            ErpCustomer customer = new ErpCustomer();
            customer.salesforceId = account.Id;
            customer.name = account.Name;
            customers.add(customer);
        }
        return customers;
    }
}
