/**
 * This file is part of the Forge Platform project
 *
 * Test support only: the Account trigger handler from the ForgeHttp scenario, which
 * sends each new Account to the ERP.
 *
 * Copyright (C) 2026 William Watson <will@cli.run>
 * https://github.com/WTWatson/apex-forge-platform
 */
public with sharing class NewAccountsBecomeErpCustomers extends ForgeTriggerHandler
{
    /** Sends Accounts to the ERP once they are inserted. */
    protected override void onTrigger(ForgeTriggerContext ctx)
    {
        if (ctx.operationType == System.TriggerOperation.AFTER_INSERT)
        {
            ForgeIntegration.start(new SendCustomersToErp(), ctx.newRecords);
        }
    }
}
