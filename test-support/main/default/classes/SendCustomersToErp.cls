/**
 * This file is part of the Forge Platform project
 *
 * Test support only: the integration from the ForgeHttp scenario, written as a
 * developer writes it.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
/** Sends new customers to the ERP and records the customer number it gives each one. */
public with sharing class SendCustomersToErp extends ForgeIntegration
{
    /** Registers each Account as an ERP customer and keeps the number the ERP assigns. */
    protected override void run(List<SObject> records)
    {
        List<Account> accounts = (List<Account>) records;
        List<ErpCustomerNumber> numbers = (List<ErpCustomerNumber>) connection('ERP')
            .post('/customers', ErpCustomer.fromAccounts(accounts))
            .readAs(List<ErpCustomerNumber>.class);
        for (Integer i = 0; i < accounts.size(); i++)
        {
            accounts[i].Erp_Customer_Number__c = numbers[i].customerNumber;
        }
    }

    /** The ERP takes at most 50 customers per call. */
    protected override Integer recordsPerCall() { return 50; }

    /** The ERP recognises a customer it already has, so a repeated call is safe. */
    protected override Boolean repeatsAreSafe() { return true; }
}
