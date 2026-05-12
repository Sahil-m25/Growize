# zoho-crm-webhook

P0 — single endpoint that mirrors Zoho CRM Contacts, LLP_Creation_Module, and LLP_UnitAllocation_Module changes into Supabase.

## Deploy

```bash
supabase functions deploy zoho-crm-webhook --no-verify-jwt
```

## Required Vault secrets

- `WEBHOOK_SECRET` — checked against `X-ARL-Webhook-Secret` header.

## Zoho workflow rules to configure

For each module: **On Create OR Edit (any field) → Webhook**.

- **URL**: `https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-crm-webhook`
- **Method**: POST
- **Headers**: `X-ARL-Webhook-Secret: <WEBHOOK_SECRET>`
- **Body** (Custom):

```json
{
  "module": "Contacts",
  "operation": "${operation}",
  "data": ${record}
}
```

Repeat for `LLP_Creation_Module` and `LLP_UnitAllocation_Module`, swapping the `module` field.

## Idempotency

Each delivery generates `idempotency_key = module + '_' + record.id + '_' + Modified_Time`. The function checks `webhook_log` and returns `{status: "duplicate"}` on a re-delivery. Payouts inside an allocation use `<allocation.id>_payout_<i>` so each UTR field-set inserts at most once.
