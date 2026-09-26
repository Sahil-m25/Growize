# App Access gate — rollout (26 Sep 2026)

New Zoho Contacts no longer get an instant invite. They sync as **Hold**
(data visible to ops, login suspended, no email). Switching Zoho
`Contacts.App_Access` to **Invite** unlocks login and sends the Growize
welcome email once, then stamps `App_Welcome_At` / `App_Welcome_Channel`
back in Zoho.

## Already done
- Zoho: `Contacts.App_Access` picklist (Hold / Invite, default Hold).
- Zoho: the 4 existing contacts set to **Invite** (they are live today).

## Deploy — in this order, same sitting
1. **SQL editor:** run `migrations/20260926000200_072_investor_app_access.sql`.
   Adds `investors.app_access` + `invited_at`, backfills everyone to
   `invited`, blocks investors from changing their own access.
2. **Edge function `zoho-crm-webhook`** -> paste `functions/zoho-crm-webhook/index.ts`, Deploy
   (JWT verification OFF, as today).
3. **Edge function `request-auth-email`** -> paste `functions/request-auth-email/index.ts`, Deploy
   (JWT verification OFF, as today).
   CLI alternative for 2+3: `supabase functions deploy zoho-crm-webhook request-auth-email --no-verify-jwt`

Both functions were recovered from the live bundles and verified
function-by-function against production: the only differences are the
App Access changes.

## Test (Claude runs this after deploy)
1. Create Zoho Contact `tech+hold1@agresearchlabs.com` (App Access = Hold).
2. Expect: investors row with app_access=hold, auth user suspended, NO email.
3. Add an EKA allotment for it -> units appear in the app DB.
4. Request a login code for it -> generic reply, no code email.
5. Switch App Access to Invite -> welcome email arrives, login works,
   Zoho shows App_Welcome_At + Channel=Email.
6. Delete the test contact in Zoho (removes it from the app too).

## Rollback
Redeploy the previous versions (Supabase keeps history). The DB columns
are additive and harmless to the old code.
