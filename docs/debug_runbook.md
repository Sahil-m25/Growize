# ARL Investor Portal — Sync Pipeline Debug Runbook

**Audience.** The on-call engineer at 2am with no context, a Slack
ping from ops, and a Supabase dashboard open.

**Companion document.** `docs/data_flow_guide.md` — read that first if
you need to understand *why* the data moves the way it does. This file
assumes you know the architecture and just need to *fix things*.

**Project ref:** `oynfhdqizebvgmaoiuax`
**Region:** Zoho IN data centre (`zohoapis.in` / `accounts.zoho.in`)
**Dashboard root:**
`https://supabase.com/dashboard/project/oynfhdqizebvgmaoiuax`

---

## 1. First-response checklist

If you don't know what's broken yet, run these five things in order.
Each one prints a slice of the pipeline's state — together they
narrow the failure to one of: gateway, secrets, function code,
upstream Zoho, or database schema.

### 1.1 Are recent webhooks failing?

Run in the Supabase SQL editor (Dashboard -> SQL Editor) or `psql`:

```sql
-- Most recent 20 webhook_log rows that are NOT a clean 'processed'.
SELECT id, event_type, status, error_message,
       received_at, processed_at,
       received_at AT TIME ZONE 'Asia/Kolkata' AS received_ist
FROM public.webhook_log
WHERE status = 'failed' OR error_message IS NOT NULL
ORDER BY received_at DESC
LIMIT 20;
```

If this returns rows for the last hour: go straight to the **Common
error catalog** (Section 2) and match the `error_message` string.

If this returns nothing but the dashboard shows stale data: it likely
means the webhook never *fired* (Zoho-side workflow misconfig, gateway
401 before our handler ran, or secret mismatch making the handler
401-return before it could write the row). Continue.

### 1.2 Is the gateway letting requests in (JWT toggle check)?

The three secret-protected functions (`zoho-crm-webhook`,
`zoho-reconcile-daily`, `sync-stale-alert`) must be deployed with
`--no-verify-jwt` so the gateway lets shared-secret requests through.
If the toggle has been reset (it sometimes is on dashboard redeploys),
unauthenticated callers get a *gateway* 401 (`UNAUTHORIZED_NO_AUTH_HEADER`)
instead of *our* 401 (`{"error":"unauthorized"}`). Smoke-test:

```bash
# WRONG secret on purpose — we expect our 401, not the gateway's.
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-crm-webhook \
  -H "Content-Type: application/json" \
  -H "X-ARL-Webhook-Secret: definitely-not-the-real-secret" \
  -d '{}'
```

Expected response body: `{"error":"unauthorized"}` with HTTP 401.

If you get `{"code":"UNAUTHORIZED_NO_AUTH_HEADER", ...}` or a 401 with
HTML, the gateway is enforcing JWT. Fix: redeploy with the flag
(see Section 5).

Repeat the same probe for the cron-secret functions:

```bash
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-reconcile-daily \
  -H "Content-Type: application/json" -H "x-arl-cron-secret: bogus" -d '{}'

curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/sync-stale-alert \
  -H "Content-Type: application/json" -H "x-arl-cron-secret: bogus" -d '{}'
```

### 1.3 Does the real secret work? (end-to-end smoke test)

Fire one harmless request with the real `WEBHOOK_SECRET` to confirm
both auth + minimum body validation respond as expected. This proves
the secret in Vault matches what the function is loading.

```bash
# Replace <WEBHOOK_SECRET> with the value from Supabase Dashboard
# -> Project Settings -> Vault -> WEBHOOK_SECRET.
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-crm-webhook \
  -H "Content-Type: application/json" \
  -H "X-ARL-Webhook-Secret: <WEBHOOK_SECRET>" \
  -d '{}'
```

Expected: HTTP 400, body `{"error":"missing module or data"}`. Anything
else (401, 5xx, gateway HTML) is a finding.

For the reconcile function (idempotent — safe to fire even at 2am):

```bash
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-reconcile-daily \
  -H "Content-Type: application/json" \
  -H "x-arl-cron-secret: <CRON_SECRET>" \
  -d '{}'
```

Expected: HTTP 200, body
`{"status":"ok","contacts":{"scanned":N,"updated":N},"llps":{...},"allocs":{...}}`.

### 1.4 What's the deployed version of each function?

```bash
# Lists deployed Edge Functions with their version + verify_jwt flag.
SUPABASE_ACCESS_TOKEN=<sbp_xxx> \
  supabase functions list --project-ref oynfhdqizebvgmaoiuax
```

Or in the Dashboard: **Functions** -> click the function -> **Code**
tab shows the current source. Cross-check against the local file:

```powershell
# PowerShell — compare deployed version to local working copy.
Get-Content C:\Users\Sahil\Downloads\ARL\arl_app\supabase\functions\zoho-crm-webhook\index.ts |
  Measure-Object -Line
```

If the deployed version doesn't match what's in git, somebody pushed
out-of-band — see Section 7 ("We pushed a broken function deploy").

### 1.5 Is the daily reconcile job actually running?

```sql
-- Most recent reconcile_daily rows (one per scheduled run).
SELECT idempotency_key, status, error_message, received_at, processed_at
FROM public.webhook_log
WHERE event_type = 'reconcile_daily'
ORDER BY received_at DESC
LIMIT 5;
```

You should see one row per day at ~01:00 UTC. If the most recent row
is more than 26 hours old, the pg_cron schedule is stuck — check the
cron job:

```sql
SELECT jobid, jobname, schedule, active, command
FROM cron.job
WHERE jobname IN ('zoho-reconcile-daily', 'sync-stale-alert-hourly');
```

And the run history (look for HTTP non-2xx in the response):

```sql
SELECT j.jobname, jr.status, jr.return_message, jr.start_time, jr.end_time
FROM cron.job_run_details jr
JOIN cron.job j ON j.jobid = jr.jobid
WHERE j.jobname IN ('zoho-reconcile-daily', 'sync-stale-alert-hourly')
ORDER BY jr.start_time DESC
LIMIT 10;
```

---

## 2. Common error catalog

Matched against the actual `error_message` text the webhook writes to
`webhook_log` (and the response body the function returns). Every
entry is something that has actually happened in this codebase. When
in doubt, copy the error string out of `webhook_log` and grep it in
this section.

### 2.1 `UNAUTHORIZED_NO_AUTH_HEADER` / gateway 401 HTML

**Symptom.** Zoho's workflow shows `HTTP 401` in its execution log;
no `webhook_log` row gets written; curl returns `{"code":"UNAUTHORIZED_NO_AUTH_HEADER",...}`
or an HTML 401 page rather than our `{"error":"unauthorized"}` JSON.

**Root cause.** The Edge Functions gateway is enforcing JWT on a
function that should be shared-secret-only. The function was deployed
without `--no-verify-jwt`, or the `verify_jwt = false` line in
`supabase/config.toml` is missing/wrong.

**Diagnosis steps.**
1. Fire the curl from Section 1.2 — confirm it's the gateway, not us.
2. Check `supabase/config.toml`:
   ```toml
   [functions.zoho-crm-webhook]
   verify_jwt = false
   ```
   (Same block must exist for `zoho-reconcile-daily` and
   `sync-stale-alert`.)
3. Dashboard -> Functions -> [function name] -> **Details**. Look for
   "Verify JWT" — it should be **OFF** for these three.

**Fix.** Redeploy with the flag explicit, regardless of toml state:

```bash
SUPABASE_ACCESS_TOKEN=<sbp_xxx> supabase functions deploy zoho-crm-webhook \
  --project-ref oynfhdqizebvgmaoiuax --no-verify-jwt
```

**Verification.** Re-run the curl from 1.2. Expect
`{"error":"unauthorized"}` HTTP 401. Re-run 1.3 with the real secret;
expect HTTP 400 `{"error":"missing module or data"}`.

### 2.2 `{"error":"unauthorized"}` (our 401)

**Symptom.** Curl with a secret header returns HTTP 401 body
`{"error":"unauthorized"}`. Zoho retries until it gives up; no
`webhook_log` row written.

**Root cause.** The secret the caller is sending does not match the
value in Supabase Vault. Most commonly: somebody rotated the Vault
secret without updating the corresponding Zoho Connection / pg_cron
schedule.

**Diagnosis.**
- For `zoho-crm-webhook`: Vault `WEBHOOK_SECRET` vs Zoho Deluge
  Connection named `Supabase Webhook Secret` (Zoho -> Setup ->
  Developer Space -> Connections).
- For `zoho-reconcile-daily` / `sync-stale-alert`: Vault `CRON_SECRET`
  vs Postgres Vault entry `cron_secret`. Compare:
  ```sql
  SELECT name, length(decrypted_secret)
  FROM vault.decrypted_secrets
  WHERE name = 'cron_secret';
  ```
  (Don't print the secret. Compare length + first 4 chars only.)

**Fix.** Re-align. Pick the canonical source (the Supabase function
env var is the source of truth) and copy that value into the caller.
See Section 6 for the full rotation procedure.

**Verification.** Re-run the 1.3 smoke test with the (now-corrected)
secret. Then fire a real Zoho test record edit and confirm a fresh
`webhook_log` row lands.

### 2.3 `{"error":"missing record id"}`

**Symptom.** HTTP 400; no investor / project / allocation update;
`webhook_log` row written with `status='received'` only (no payload
data fields).

**Root cause.** Zoho posted with an empty body OR the body had no
`data.id` field. Two known triggers:
1. Deluge function's HTTP step is using `parameters: <Map variable>`
   instead of `parameters: body_text` (a string). The string form
   posts the full JSON; the Map form sometimes drops/mangles fields.
2. The Module Parameters section in the Zoho Webhook builder is set
   to "None" while Body Type is also "None" — nothing gets sent.

**Diagnosis.** Pull the most recent failure and look at the recorded
payload:

```sql
SELECT payload, received_at
FROM public.webhook_log
WHERE error_message LIKE '%missing record id%'
   OR status = 'received'  -- e.g. logged but never processed
ORDER BY received_at DESC
LIMIT 5;
```

If `payload.data` is `{}` or absent, the body is empty.

**Fix.** In the Deluge custom function (Zoho -> Setup -> Functions),
edit the HTTP call to:

```deluge
response = invokeurl
[
  url : "https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-crm-webhook"
  type : POST
  parameters : body_text   // body_text is a STRING (JSON-encoded), not a Map
  headers : {"X-ARL-Webhook-Secret": webhook_secret, "Content-Type": "application/json"}
];
```

**Verification.** Edit a test Contact in Zoho. New `webhook_log` row
should land within ~5s with `status='processed'`.

### 2.4 `{"error":"missing Customer.id in allocation payload"}` (or `LLP.id`)

**Symptom.** Allocation handler throws. `webhook_log.error_message`
contains `missing Customer.id in allocation payload` or `missing LLP.id`.

**Root cause.** The Deluge function flattened the lookup field to a
plain string ID rather than the nested `{id, name}` map that
`handleAllocation` expects. `handleAllocation` does
`d.Customer.id` and crashes if `d.Customer` is a string.

**Fix.** In `Push_Allocation_To_Supabase`, the body must pass
`Customer` and `LLP` as **maps**, not strings:

```deluge
data_map = Map();
data_map.put("id", record.get("id"));
data_map.put("Customer", {"id": record.get("Customer").get("id")});
data_map.put("LLP",      {"id": record.get("LLP").get("id")});
// ...all the financial fields...
body_text = data_map.toString();
```

**Verification.** Trigger the workflow on a test allocation. The
`webhook_log` row should now have `payload.data.Customer.id` populated
and `status='processed'`.

### 2.5 `invalid input syntax for type numeric: ""`

**Symptom.** Webhook returns 500. `error_message` reads
`projects update failed: invalid input syntax for type numeric: ""`
(or `investor_units upsert failed: ...`).

**Root cause.** A numeric column got an empty string. Deluge serialises
unset numeric fields as `""` instead of `null`. The webhook handler
has an `asNumber()` helper that converts `""` -> `undefined` (which
drops the field from the upsert), but if a new numeric column was
added without wrapping it in `asNumber()` the failure resurfaces.

**Diagnosis.** Grep the offending handler for unwrapped numerics:

```powershell
# All non-asNumber numeric casts in the webhook.
Select-String -Path C:\Users\Sahil\Downloads\ARL\arl_app\supabase\functions\zoho-crm-webhook\index.ts `
  -Pattern "as number"
```

The reconcile handler is the more common culprit — it currently uses
raw casts (`d.Total_Units as number | undefined`) instead of `asNumber`,
so a CRM value of `""` will reach Postgres unfiltered.

**Fix.**
- Webhook: wrap the offending column with `asNumber(d.Field_Name)`.
- Reconcile: same. Both files have the helper defined at the top.
- Long term: also fix in Deluge (`if (val == "") val = null;`) for
  defence in depth.

**Verification.** Replay the failing record (edit & save in Zoho to
re-fire the workflow), confirm `webhook_log` row goes to `processed`.

### 2.6 `invalid input syntax for type date: ""`

Same shape as 2.5 but for a date column. Fix: wrap with `asDate()` (or
`asLaunchYearDate()` for the year-picklist `Launch_Year` column).

### 2.7 CHECK constraint violation (e.g. `investors_kyc_status_check`)

**Symptom.** `error_message` contains
`new row for relation "investors" violates check constraint "investors_kyc_status_check"`.

**Root cause.** Handler wrote a value Postgres's CHECK enum doesn't
allow. The most common case is `kyc_status` — Zoho's picklist has
`Completed`, `In Progress`, `Not Started`; Postgres allows only
`pending|in_progress|verified|rejected`.

**Fix.** Use the existing `mapKycStatus()` helper (in both
`zoho-crm-webhook/index.ts` and `zoho-reconcile-daily/index.ts`). If
the new violation is on a different column, add a similar mapping
helper. **Do not** loosen the CHECK constraint without product
review — the constraint is the safety net that catches handler bugs.

**Verification.**

```sql
-- After re-firing the Zoho workflow:
SELECT zoho_contact_id, kyc_status, last_synced_at
FROM public.investors
WHERE zoho_contact_id = '<the contact id>';
```

### 2.8 Silent success — webhook returns 200 but row is unchanged

**Symptom.** `webhook_log.status='processed'`, no `error_message`, but
the database row's `updated_at` hasn't moved and the new field value
isn't there.

**Root cause.** Pre-fix code did `await supabase.from(t).update(...)`
without destructuring `{error}`. PostgREST returns a JSON error
body but doesn't throw — the row just isn't updated, and the
audit log shows everything succeeded.

This was patched in the 2026-05-11 deploy ("silent-fail audit patches
(3 fns)") but new code paths can re-introduce it.

**Diagnosis.** Grep the handlers for bare updates/upserts:

```powershell
# Look for unguarded .update or .upsert calls.
Select-String -Path C:\Users\Sahil\Downloads\ARL\arl_app\supabase\functions\*\index.ts `
  -Pattern "await supabase[\s\S]*?\.(update|upsert)\("
```

Each should be followed by `if (err) throw ...` or `const { error } = await`.

**Fix.** Destructure `{ error }`, throw on failure so the route
wrapper marks the `webhook_log` row `failed`:

```ts
const { error: updErr } = await supabase.from("investors").update(update)
  .eq("zoho_contact_id", d.id as string);
if (updErr) throw new Error(`investors update failed: ${updErr.message}`);
```

**Verification.** Re-fire the webhook with deliberately-bad data
(e.g. value outside the CHECK enum) and confirm the row now lands as
`status='failed'` with a real `error_message`.

### 2.9 `Zoho token refresh failed: {"error":"invalid_client"}`

**Symptom.** `zoho-reconcile-daily` returns 500 with this message; the
daily `reconcile_daily` row is `status='failed'`.

**Root cause.** The OAuth credentials (`ZOHO_CLIENT_ID`,
`ZOHO_CLIENT_SECRET`, `ZOHO_REFRESH_TOKEN`) are stale. Refresh tokens
can be revoked by Zoho if (a) the client is regenerated, (b) the user
who issued it loses CRM access, (c) the token sat unused beyond
Zoho's idle limit.

**Diagnosis.** Try a minimal token refresh against the IN data
centre. From a workstation with curl:

```bash
curl -sS -X POST https://accounts.zoho.in/oauth/v2/token \
  -d "refresh_token=<ZOHO_REFRESH_TOKEN>" \
  -d "client_id=<ZOHO_CLIENT_ID>" \
  -d "client_secret=<ZOHO_CLIENT_SECRET>" \
  -d "grant_type=refresh_token"
```

If you get `{"error":"invalid_client"}` here, it's not our code — the
creds are dead.

**Fix.**
1. Log into Zoho API Console (`https://api-console.zoho.in/`).
2. Find the Server-based Application named "ARL Investor Portal
   Reconcile" (or create one if missing).
3. Regenerate Client Secret if needed.
4. Use the self-client auth flow to mint a new auth code:
   - In the API Console, go to "Self Client" -> Generate Code.
   - Scopes: `ZohoCRM.modules.ALL`, `ZohoCRM.settings.ALL`,
     `ZohoCRM.users.ALL`. Duration: 10 minutes.
5. Exchange the auth code for a refresh token:
   ```bash
   curl -sS -X POST https://accounts.zoho.in/oauth/v2/token \
     -d "grant_type=authorization_code" \
     -d "client_id=<new_client_id>" \
     -d "client_secret=<new_client_secret>" \
     -d "code=<auth_code_from_step_4>"
   ```
6. Take the `refresh_token` from the response and update Vault:
   ```bash
   supabase secrets set --project-ref oynfhdqizebvgmaoiuax \
     ZOHO_CLIENT_ID=<new_id> \
     ZOHO_CLIENT_SECRET=<new_secret> \
     ZOHO_REFRESH_TOKEN=<new_refresh_token>
   ```

**Verification.** Fire the reconcile function manually (Section 1.3) —
it does a token refresh on every call. Watch for a 200.

### 2.10 `REQUIRED_PARAM_MISSING: fields`

**Symptom.** `zoho-reconcile-daily` 500s on the first page fetch:
`zoho fetch Contacts page 1 failed: 400 {"code":"REQUIRED_PARAM_MISSING","details":{"api_name":"fields"},...}`.

**Root cause.** Zoho CRM v3 list endpoints require an explicit `fields`
query parameter (no `fields=*` shortcut anymore). The
`fetchModuleSince()` call must pass the per-module FIELDS constant.

**Diagnosis.** Should be unreachable in current code — `fetchModuleSince`
already passes `fields`. If it triggers anyway, somebody added a new
module-fetch call without wiring through the constant.

**Fix.** Pass the correct constant. In `zoho-reconcile-daily/index.ts`:

```ts
const records = await fetchModuleSince("Contacts", CONTACT_FIELDS, since, token);
// not: fetchModuleSince("Contacts", "*", since, token)
```

**Verification.** Re-fire reconcile.

### 2.11 `investor_units upsert failed: investor not found for zoho_contact_id ...`

**Symptom.** Allocation webhook fails. Customer exists in Zoho but
not in Supabase. `error_message` quotes the missing `zoho_contact_id`.

**Root cause.** `onboard-investor` was never run for this person, so
no `investors` row exists for the allocation to FK onto.

**Diagnosis.**

```sql
SELECT id, email, zoho_contact_id, onboarded_at
FROM public.investors
WHERE zoho_contact_id = '<the missing id>';
-- 0 rows expected; that's the problem.
```

**Fix.** Choose one:
- (Preferred) Onboard the investor properly:
  ```bash
  curl -sS -X POST \
    https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/onboard-investor \
    -H "Content-Type: application/json" \
    -H "X-ARL-Admin-Secret: <ADMIN_SECRET>" \
    -d '{"email":"x@y.com","name":"X Y","arl_id":"ARL-00xxx","zoho_contact_id":"<the missing id>"}'
  ```
- (Manual) Insert a placeholder row, then have ARL re-send the invite
  from Studio. Only do this if you know what you're doing.

After the investor row exists, re-fire the Zoho allocation workflow
(edit & save the Allocation record in CRM) to replay the failed
webhook.

**Verification.**

```sql
SELECT iu.id, iu.zoho_allocation_id, i.email, p.name AS project_name
FROM public.investor_units iu
JOIN public.investors i ON i.id = iu.investor_id
JOIN public.projects p  ON p.id = iu.project_id
WHERE iu.zoho_allocation_id = '<the allocation id>';
```

### 2.12 Webhook fires, returns 200, but the Supabase row didn't update

If `webhook_log` shows `status='processed'` but the row content is
stale, it's almost always one of:

1. **Silent CHECK violation** (2.8) — confirm by running the same
   update SQL by hand and watching it fail.
2. **Stale-write guard rejected the update.** `handleContact` skips
   the update if `incomingUpdated <= cur.updated_at`. If Zoho sends
   stale `Modified_Time` (some Deluge functions overwrite it with
   `zoho.currenttime` accidentally), our newer copy wins. Check by
   comparing `webhook_log.payload->data->>'Modified_Time'` against
   `investors.updated_at`.
3. **Onboard never ran** (2.11). Webhook returns silently and logs
   `status='processed'` because no exception was raised.

### 2.13 Flutter app shows stale data

**Symptom.** Investor calls support saying their portfolio is wrong /
KYC didn't flip / new payout isn't visible.

**Diagnosis.** Decide whether the staleness is server-side or
client-side:

```sql
-- Server-side freshness for one investor.
SELECT i.name, i.zoho_contact_id, i.updated_at, i.last_synced_at,
       NOW() - i.last_synced_at AS sync_age
FROM public.investors i
WHERE i.email = '<investor@email>';
```

If `last_synced_at` is recent (< 1 hour): Supabase is fine. The app
has stale local cache (Hive `ResilientCache`) or the user hasn't
pulled-to-refresh. Ask the investor to force-close and reopen the
app, or to pull-to-refresh on the affected screen.

If `last_synced_at` is old (> 6 hours for investors): the sync path
upstream is broken. Go to Section 1.1.

---

## 3. Each function's failure modes

### 3.1 `zoho-crm-webhook`

**Auth header.** `X-ARL-Webhook-Secret: <WEBHOOK_SECRET>`. Compared
constant-time against `WEBHOOK_SECRET` env var.

**Manual fire (contact update example).**

```bash
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-crm-webhook \
  -H "Content-Type: application/json" \
  -H "X-ARL-Webhook-Secret: <WEBHOOK_SECRET>" \
  -d '{
    "module": "Contacts",
    "operation": "update",
    "data": {
      "id": "<zoho_contact_id>",
      "Modified_Time": "2026-05-11T12:00:00+05:30",
      "First_Name": "Test", "Last_Name": "Investor",
      "Email": "test@example.com",
      "KYC": "In Progress"
    }
  }'
```

**Expected success.** HTTP 200 body `{"status":"ok"}` (or
`{"status":"duplicate"}` if you replay the same `idempotency_key`).

**Common error responses.**
| Status | Body | Meaning |
|---|---|---|
| 401 | `{"error":"unauthorized"}` | Bad secret. |
| 400 | `{"error":"missing module or data"}` | Body had no `module` and no record fields. |
| 400 | `{"error":"missing record id"}` | `data.id` was empty. |
| 500 | `{"error":"...","detail":"..."}` | Handler exception — read `error`. |

**Where to look in logs.** Dashboard -> Functions -> `zoho-crm-webhook`
-> **Logs** tab (raw stdout/stderr from `console.error`) and
**Invocations** tab (per-request metadata, status code, duration).
The `webhook_log` table is the persistent record — always start there.

### 3.2 `zoho-reconcile-daily`

**Auth header.** `x-arl-cron-secret: <CRON_SECRET>`.

**Manual fire.**

```bash
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-reconcile-daily \
  -H "Content-Type: application/json" \
  -H "x-arl-cron-secret: <CRON_SECRET>" \
  -d '{}'
```

**Expected success.** HTTP 200, body:

```json
{
  "status": "ok",
  "contacts": {"scanned": 42, "updated": 3},
  "llps":     {"scanned": 5,  "updated": 0},
  "allocs":   {"scanned": 12, "updated": 1}
}
```

**Common error responses.**
| Status | Body fragment | Meaning |
|---|---|---|
| 401 | `unauthorized` | Bad `CRON_SECRET`. |
| 500 | `Zoho token refresh failed: ...` | See 2.9. |
| 500 | `zoho fetch <module> page N failed: ...` | Upstream Zoho 4xx/5xx — read body. |
| 500 | `<table> upsert failed: ...` | Same coercion/CHECK issues as 2.5-2.7. |

**Where to look.** Dashboard -> Functions -> `zoho-reconcile-daily`
-> Logs (you'll see the per-page fetch URLs and any thrown errors).
`webhook_log` rows with `event_type='reconcile_daily'` are the
persistent summary.

### 3.3 `sync-stale-alert`

**Auth header.** `x-arl-cron-secret: <CRON_SECRET>`.

**Manual fire.**

```bash
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/sync-stale-alert \
  -H "Content-Type: application/json" \
  -H "x-arl-cron-secret: <CRON_SECRET>" \
  -d '{}'
```

**Expected success.** HTTP 200, body:

```json
{
  "status": "ok",
  "alerts": 0,
  "summary": [
    {"table":"llps","rows":5,"age_seconds":3122,"threshold":86400,"alert":false},
    {"table":"investors","rows":140,"age_seconds":782,"threshold":21600,"alert":false},
    ...
  ]
}
```

Any `alert: true` entry in `summary` means a `sync_alerts` row was
inserted — go diagnose the underlying staleness via Section 1.1.

**Where to look.** Dashboard -> Functions -> `sync-stale-alert` -> Logs.
Persistent record: `public.sync_alerts`:

```sql
SELECT table_name, age_seconds, threshold_secs, detail, created_at
FROM public.sync_alerts
ORDER BY created_at DESC
LIMIT 20;
```

### 3.4 `onboard-investor`

**Auth header.** `X-ARL-Admin-Secret: <ADMIN_SECRET>`.

**Manual fire.**

```bash
curl -sS -i -X POST \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/onboard-investor \
  -H "Content-Type: application/json" \
  -H "X-ARL-Admin-Secret: <ADMIN_SECRET>" \
  -d '{
    "email": "newinvestor@example.com",
    "name":  "New Investor",
    "arl_id": "ARL-00501",
    "zoho_contact_id": "4567000000123456",
    "phone": "+919812345678",
    "salutation": "Mr"
  }'
```

**Expected success.** HTTP 200:

```json
{
  "investor_id": "<uuid>",
  "arl_id": "ARL-00501",
  "message": "Invite sent — investor will receive a password-setup email"
}
```

**Common error responses.**
| Status | Body | Meaning |
|---|---|---|
| 400 | `{"error":"email, name, arl_id are required"}` | Body missing required field. |
| 401 | `{"error":"unauthorized"}` | Bad `ADMIN_SECRET`. |
| 409 | `{"error":"investor already exists","investor_id":"..."}` | Email already in `investors`. |
| 500 | `{"error":"invite failed","detail":"..."}` | `auth.admin.inviteUserByEmail` rejected — usually email-format or duplicate auth.users. |
| 500 | `{"error":"investor insert failed","detail":"..."}` | Auth user created OK but `investors` insert failed (CHECK violation, duplicate `arl_id`, etc.). Function attempts to delete the auth user as cleanup. |

**Where to look.** Dashboard -> Functions -> `onboard-investor` ->
Logs. There is no persistent audit log for this function (it's not
written to `webhook_log`) — the Edge Function logs are the only
record of failed invites.

---

## 4. Database verification queries

Copy-paste library. Run in Dashboard -> SQL Editor, or via
`psql "<connection string>"`.

### 4.1 Is the sync alive? (most recent webhook per event type)

```sql
SELECT DISTINCT ON (event_type)
       event_type, status, received_at, processed_at, error_message
FROM public.webhook_log
ORDER BY event_type, received_at DESC;
```

Should include rows for `Contacts.update`, `LLP_Creation_Module.update`,
`LLP_UnitAllocation_Module.update`, and `reconcile_daily`. If any
`event_type` is missing entirely or older than a day, that branch of
the pipeline is dead.

### 4.2 What failed in the last 24 hours?

```sql
SELECT event_type, status, error_message,
       received_at AT TIME ZONE 'Asia/Kolkata' AS received_ist
FROM public.webhook_log
WHERE received_at > NOW() - INTERVAL '24 hours'
  AND (status = 'failed' OR error_message IS NOT NULL)
ORDER BY received_at DESC;
```

### 4.3 Is the daily reconcile running?

```sql
SELECT idempotency_key, status,
       received_at AT TIME ZONE 'Asia/Kolkata' AS started_ist,
       processed_at - received_at AS duration,
       payload
FROM public.webhook_log
WHERE event_type = 'reconcile_daily'
ORDER BY received_at DESC
LIMIT 7;
```

Expect roughly one row per day at ~01:00 UTC (06:30 IST). Gaps mean
pg_cron didn't fire.

### 4.4 What's stale right now?

```sql
-- Per-table snapshot — the same data sync-stale-alert reads.
SELECT * FROM public.sync_status;

-- Same data with thresholds applied:
WITH thresholds(table_name, threshold_secs) AS (
  VALUES ('llps', 86400), ('projects', 86400),
         ('investors', 21600), ('investor_units', 7200)
)
SELECT s.table_name, s.rows, s.max_synced_at,
       EXTRACT(EPOCH FROM (NOW() - s.max_synced_at))::int AS age_seconds,
       t.threshold_secs,
       (s.max_synced_at IS NULL
        OR EXTRACT(EPOCH FROM (NOW() - s.max_synced_at)) > t.threshold_secs) AS stale
FROM public.sync_status s
JOIN thresholds t ON t.table_name = s.table_name
ORDER BY age_seconds DESC NULLS FIRST;
```

### 4.5 Investors that look stale individually (>24h since last sync)

```sql
SELECT id, name, email, zoho_contact_id, last_synced_at, updated_at,
       NOW() - last_synced_at AS sync_age
FROM public.investors
WHERE last_synced_at < NOW() - INTERVAL '24 hours'
   OR last_synced_at IS NULL
ORDER BY last_synced_at NULLS FIRST
LIMIT 50;
```

Repeat the same shape for `llps`, `projects`, `investor_units` as
needed.

### 4.6 Verify the Zoho mapping for one record

Given a `zoho_contact_id` ARL gave you, dump the full picture:

```sql
SELECT i.id, i.name, i.email, i.arl_id, i.kyc_status, i.zoho_contact_id,
       i.updated_at, i.last_synced_at, i.onboarded_at
FROM public.investors i
WHERE i.zoho_contact_id = '<paste id>';

-- All allocations for that investor:
SELECT iu.zoho_allocation_id, iu.issued_units, iu.capital_invested,
       iu.allocation_status, iu.customer_status, iu.last_synced_at,
       p.name AS project_name, l.zoho_llp_id
FROM public.investor_units iu
JOIN public.projects p ON p.id = iu.project_id
JOIN public.llps     l ON l.id = p.llp_id
JOIN public.investors i ON i.id = iu.investor_id
WHERE i.zoho_contact_id = '<paste id>';

-- All payouts for that investor:
SELECT po.utr, po.amount, po.payout_date, po.status, po.idempotency_key
FROM public.payouts po
JOIN public.investors i ON i.id = po.investor_id
WHERE i.zoho_contact_id = '<paste id>'
ORDER BY po.payout_date DESC NULLS LAST;
```

### 4.7 Orphan detection — investors missing from auth.users

```sql
SELECT i.id, i.email, i.name, i.onboarded_at
FROM public.investors i
LEFT JOIN auth.users u ON u.id = i.id
WHERE u.id IS NULL;
-- Should always be empty. Investors.id is REFERENCES auth.users(id)
-- ON DELETE CASCADE, but if FK enforcement gets disabled (or someone
-- inserts via direct SQL) you may see drift.
```

And the converse — auth users with no `investors` row (an
`onboard-investor` half-failure):

```sql
SELECT u.id, u.email, u.created_at
FROM auth.users u
LEFT JOIN public.investors i ON i.id = u.id
WHERE i.id IS NULL
  AND u.email NOT IN ('tech@agresearchlabs.com')  -- exclude staff
ORDER BY u.created_at DESC;
```

### 4.8 Duplicate detection — multiple investors per Zoho contact

```sql
-- zoho_contact_id is UNIQUE but nullable; multiple NULLs are allowed.
-- Both shapes matter:

-- (a) Same non-null zoho_contact_id mapped twice (shouldn't happen
--     because of the UNIQUE index; if it does, the index is gone):
SELECT zoho_contact_id, COUNT(*) AS n,
       array_agg(email ORDER BY onboarded_at) AS emails
FROM public.investors
WHERE zoho_contact_id IS NOT NULL
GROUP BY zoho_contact_id
HAVING COUNT(*) > 1;

-- (b) Multiple investors with NULL zoho_contact_id — risk of the same
--     CRM contact getting linked twice on retry:
SELECT id, email, name, arl_id, onboarded_at
FROM public.investors
WHERE zoho_contact_id IS NULL
ORDER BY onboarded_at DESC;
```

If (b) returns more than a handful, see `docs/data_flow_guide.md`
Section 8 item 2 — `zoho_contact_id` should arguably be `NOT NULL`
or have a partial UNIQUE index excluding NULL. Until that ships,
ARL staff must always pass `zoho_contact_id` to `onboard-investor`.

### 4.9 CHECK constraint inventory

When a write fails with a CHECK violation, know what the constraints
*are*:

```sql
SELECT n.nspname AS schema,
       c.relname AS table_name,
       con.conname AS constraint_name,
       pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE con.contype = 'c'
  AND n.nspname = 'public'
  AND c.relname IN ('investors', 'projects', 'llps',
                    'investor_units', 'payouts', 'webhook_log',
                    'notifications', 'sync_alerts')
ORDER BY c.relname, con.conname;
```

### 4.10 Webhook log payload inspection (sanitised)

```sql
-- Look at the actual normalised payload for a recent failure:
SELECT id, event_type, status, error_message,
       payload->'_shape' AS request_shape,
       payload->'data' AS sanitized_data,
       received_at
FROM public.webhook_log
WHERE status = 'failed'
ORDER BY received_at DESC
LIMIT 5;
```

Remember: PAN, bank account, Aadhaar are masked in `payload` (see
`sanitizeForLogging()` in `zoho-crm-webhook/index.ts`). If you need
the raw values for debugging, get them from Zoho — never log raw PII
into Supabase.

---

## 5. Redeploying a function safely

Every Edge Function in this project must be deployed with
`--no-verify-jwt` if it's one of the three secret-protected ones
(`zoho-crm-webhook`, `zoho-reconcile-daily`, `sync-stale-alert`).
`onboard-investor` keeps the default (`verify_jwt=true`) because the
admin secret check runs inside the handler — the JWT gate is fine.

`supabase/config.toml` *pins* `verify_jwt=false` for those three
functions but it's been observed to occasionally re-enable on
deploys, so the CLI flag is belt-and-suspenders.

### 5.1 The procedure

1. **Make code change locally.**
2. **Static-check.** Deno will catch most types but Edge Runtime is
   not Deno-flavoured 1:1 — read the diff carefully. Specifically:
   - Any new `.update()` / `.upsert()` MUST destructure `{ error }`
     and throw on it (see 2.8).
   - Any new numeric / date column MUST go through `asNumber()` /
     `asDate()` (see 2.5).
   - Any new picklist/enum write MUST go through a mapping helper
     (see 2.7).
3. **Deploy.** Always pass `--no-verify-jwt` for the three
   shared-secret functions. The SUPABASE_ACCESS_TOKEN must be a
   personal access token (the SBP-prefixed kind from
   <https://supabase.com/dashboard/account/tokens>).

   ```powershell
   # PowerShell:
   $env:SUPABASE_ACCESS_TOKEN = "<sbp_personal_access_token>"
   supabase functions deploy zoho-crm-webhook `
     --project-ref oynfhdqizebvgmaoiuax `
     --no-verify-jwt
   ```

   ```bash
   # Bash:
   SUPABASE_ACCESS_TOKEN=<sbp_xxx> \
     supabase functions deploy zoho-crm-webhook \
     --project-ref oynfhdqizebvgmaoiuax \
     --no-verify-jwt
   ```
4. **Smoke-test immediately.** Run the curl from Section 1.2 (bad
   secret -> our 401, not gateway 401) and Section 1.3 (real secret ->
   400 missing fields). If either is wrong, *redeploy with the flag
   explicit*. Do not assume "it'll re-enable later".
5. **Watch the first real fire.** Dashboard -> Functions -> [function]
   -> **Invocations**. The first post-deploy invocation should be
   green. If it errors, you have a hot rollback window of seconds
   to revert.
6. **Compare deployed code to local.** Dashboard -> Functions ->
   [function] -> **Code** tab. Skim the top 40 lines and the
   bottom 40 — easy to spot if your build picked up the wrong file
   or stripped imports. (Yes, this has happened. WARNING about
   Docker not running in the deploy log is *normal* — Supabase
   bundles via remote builder when Docker is unavailable.)
7. **Promote** by editing the Zoho workflow rule (if any) to point at
   the new URL — but in practice the URL is constant
   (`/functions/v1/<name>`), so nothing changes on the Zoho side.

### 5.2 Deploying all four at once

```bash
for fn in zoho-crm-webhook zoho-reconcile-daily sync-stale-alert; do
  SUPABASE_ACCESS_TOKEN=<sbp_xxx> \
    supabase functions deploy $fn \
    --project-ref oynfhdqizebvgmaoiuax \
    --no-verify-jwt
done

# onboard-investor uses default verify_jwt=true:
SUPABASE_ACCESS_TOKEN=<sbp_xxx> \
  supabase functions deploy onboard-investor \
  --project-ref oynfhdqizebvgmaoiuax
```

---

## 6. Rotating secrets

All secrets live in Supabase Vault (set via `supabase secrets set` or
Dashboard -> Project Settings -> Edge Functions -> Secrets). The
Vault entry named `cron_secret` is *separately* readable by
`pg_cron`; rotating `CRON_SECRET` requires updating it in both places.

### 6.1 `WEBHOOK_SECRET`

Used by `zoho-crm-webhook` only.

```bash
# 1. Generate new secret (32 bytes hex):
NEW=$(openssl rand -hex 32)
echo "$NEW"  # write it down, you'll need it for Zoho

# 2. Update Vault:
supabase secrets set --project-ref oynfhdqizebvgmaoiuax \
  WEBHOOK_SECRET="$NEW"

# 3. Update Zoho:
#    Zoho CRM -> Setup -> Developer Space -> Connections.
#    Edit the connection named "Supabase Webhook Secret"
#    (it's referenced by name in the Deluge functions:
#     Push_Contact_To_Supabase / Push_LLP_To_Supabase / Push_Allocation_To_Supabase).
#    Paste the new value into the "Webhook Secret" field. Save.

# 4. Verify by smoke-testing — Section 1.3 curl with the new secret.
# 5. Trigger any test record edit in Zoho; confirm a new
#    webhook_log row lands with status='processed'.
```

### 6.2 `ADMIN_SECRET`

Used by `onboard-investor` only. No automated caller — only ARL
staff use it from Postman / Studio.

```bash
NEW=$(openssl rand -hex 32)
supabase secrets set --project-ref oynfhdqizebvgmaoiuax \
  ADMIN_SECRET="$NEW"

# Update the Postman collection / internal onboarding doc / any
# server-side automation that calls onboard-investor.
```

No deploy required (functions read env at cold start; the next
invocation picks it up).

### 6.3 `CRON_SECRET`

Used by `zoho-reconcile-daily`, `sync-stale-alert`, `gallery-sync`,
`health-check`. Lives in BOTH the function env *and* the Postgres
Vault entry `cron_secret` (which pg_cron reads).

```bash
NEW=$(openssl rand -hex 32)

# 1. Update function env (used when curl-firing manually):
supabase secrets set --project-ref oynfhdqizebvgmaoiuax \
  CRON_SECRET="$NEW"
```

```sql
-- 2. Update the Postgres Vault entry that pg_cron reads.
-- Connect via psql or Dashboard SQL Editor.

SELECT vault.update_secret(
  (SELECT id FROM vault.secrets WHERE name = 'cron_secret'),
  '<NEW>',
  'cron_secret',
  'Shared secret used by pg_cron HTTP calls to Edge Functions.'
);

-- Verify:
SELECT name, length(decrypted_secret), updated_at
FROM vault.decrypted_secrets
WHERE name = 'cron_secret';
```

The pg_cron schedules in migration 024 read the Vault entry at run
time, so no migration redeploy is needed — the next cron tick
picks up the new value automatically.

**Verification.** Wait for the next hourly `sync-stale-alert` tick
(or force-fire it via curl), then check the cron run history:

```sql
SELECT j.jobname, jr.status, jr.return_message, jr.start_time
FROM cron.job_run_details jr
JOIN cron.job j ON j.jobid = jr.jobid
WHERE j.jobname IN ('zoho-reconcile-daily', 'sync-stale-alert-hourly')
ORDER BY jr.start_time DESC LIMIT 5;
```

`return_message` should contain a 2xx response, not a 401.

### 6.4 `ZOHO_CLIENT_ID` / `ZOHO_CLIENT_SECRET` / `ZOHO_REFRESH_TOKEN`

Full procedure in Section 2.9. Summary:

1. Zoho API Console (`https://api-console.zoho.in/`) -> regenerate
   Client Secret or create a new Server-based Application.
2. Self-Client -> Generate Code (scopes: `ZohoCRM.modules.ALL`,
   `ZohoCRM.settings.ALL`, `ZohoCRM.users.ALL`, duration 10 min).
3. Exchange the auth code for a refresh token using the curl in
   Section 2.9 step 5.
4. `supabase secrets set` all three values.
5. Manually fire `zoho-reconcile-daily` (Section 1.3) — the function
   refreshes the access token on every call, so this proves the new
   creds work without waiting for the daily cron.

---

## 7. Disaster recovery scenarios

### 7.1 "All webhooks have been failing for 12 hours"

**Goal.** Backfill the missed updates from Zoho.

1. Diagnose root cause first (Section 2) — otherwise you'll just
   re-fail the same way.
2. Once fixed (e.g. secret rotated, code patched, gateway JWT toggle
   off), fire the reconcile manually:
   ```bash
   curl -sS -i -X POST \
     https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-reconcile-daily \
     -H "Content-Type: application/json" \
     -H "x-arl-cron-secret: <CRON_SECRET>" \
     -d '{}'
   ```
3. The reconcile pulls everything modified in the last 25 hours
   (`COLD_START_LOOKBACK_MS`). If the outage was longer than 25h,
   temporarily edit the function to widen the window:
   - Open `supabase/functions/zoho-reconcile-daily/index.ts`.
   - Change `COLD_START_LOOKBACK_MS = 25 * 60 * 60 * 1000` to
     e.g. `48 * 60 * 60 * 1000` (or more).
   - Deploy (Section 5).
   - Fire it.
   - Revert and re-deploy.
4. Verify drift cleared:
   ```sql
   SELECT * FROM public.sync_status;
   ```
   `max_synced_at` should be within minutes of NOW().

### 7.2 "Supabase project is paused"

If the project paused due to inactivity / billing, Edge Functions
return 503 and the database is unreachable.

1. Dashboard root -> **Resume** button at the top of the project
   overview.
2. Wait ~60s for the database to come back up.
3. Once `SELECT 1;` works in SQL Editor, fire `zoho-reconcile-daily`
   manually (Section 1.3) to backfill anything missed during the pause.
4. Resolve the underlying reason (probably billing — upgrade the
   project if you haven't).

### 7.3 "We pushed a broken function deploy and it's actively breaking sync"

Goal: roll back to the previous version FAST. Supabase doesn't keep
git-style history of deployed functions — your rollback artifact is
the local file.

1. **If the previous version is in git locally:**
   ```bash
   cd C:\Users\Sahil\Downloads\ARL\arl_app
   git log --oneline supabase/functions/<name>/index.ts
   git checkout <previous-good-sha> -- supabase/functions/<name>/index.ts
   SUPABASE_ACCESS_TOKEN=<sbp_xxx> \
     supabase functions deploy <name> \
     --project-ref oynfhdqizebvgmaoiuax --no-verify-jwt
   ```
2. **If you saved the previous version locally** (e.g. in
   `docs/testing/runs/`): copy it over `index.ts` and redeploy.
3. **If you only have the Dashboard "Code" tab view of the old
   version:** copy-paste the previous version into `index.ts`
   manually, then deploy.
4. After rollback, smoke-test (Section 1.3) before you investigate
   what went wrong with the broken deploy.

### 7.4 "Customer says their data is wrong — fix one record"

Goal: force a single record back into sync without waiting for the
daily cron.

1. Find the `zoho_contact_id` / `zoho_llp_id` / `zoho_allocation_id`
   for the affected record (ARL staff has the Zoho UI).
2. Open the record in Zoho, make a no-op edit (toggle a field, then
   set it back; save). This re-fires the workflow rule and POSTs to
   our webhook.
3. Within ~5 seconds, the Supabase row should update. Verify via
   Section 4.6.
4. If the webhook errored (visible in `webhook_log`), match the
   error to Section 2 and fix.
5. If the webhook succeeded but the data still looks wrong, it's
   the source data in Zoho that's wrong, not the sync. Push back
   to ARL staff to correct in CRM.

### 7.5 "Zoho OAuth token was revoked accidentally"

(Same as 2.9; calling it out as a DR scenario because it tends to
discover itself at 02:00 IST when the daily reconcile run fails.)

1. Confirm by hitting `https://accounts.zoho.in/oauth/v2/token` with
   the stored refresh token (Section 2.9). If you get `invalid_client`
   or `invalid_grant`, the token is dead.
2. Re-issue via the Self Client flow in API Console (Section 2.9).
3. Update Vault (`ZOHO_CLIENT_ID`/`ZOHO_CLIENT_SECRET`/`ZOHO_REFRESH_TOKEN`).
4. Fire `zoho-reconcile-daily` manually to backfill anything missed
   while the token was dead.

### 7.6 "Cron isn't firing at all"

The `pg_cron` extension is enabled in migration `014`. If the cron
jobs are gone entirely (e.g. someone disabled them, or the database
was restored from a snapshot without the schedule):

```sql
-- Are pg_cron and pg_net even installed?
SELECT extname, extversion FROM pg_extension
WHERE extname IN ('pg_cron', 'pg_net');

-- Are the jobs scheduled?
SELECT jobname, schedule, active FROM cron.job;
```

If a job is missing, re-run the relevant migration:
`supabase/migrations/20260507120100_024_schedule_reconcile_and_alert.sql`
(or whichever one defines the missing job — `014` for the original
gallery-sync schedule, `022` for health-check). You may need to
`SELECT cron.unschedule('<jobname>');` first to clear stale dupes.

---

## 8. Glossary

| Term | Meaning |
|---|---|
| **ARL** | AgResearch Labs — the operating company. |
| **ZCID** | Shorthand for `zoho_contact_id` — the Zoho CRM-internal record ID of a Contact, used as the upsert key in the `investors` table. |
| **Deluge** | Zoho's proprietary scripting language. The Zoho-side push functions (`Push_Contact_To_Supabase`, `Push_LLP_To_Supabase`, `Push_Allocation_To_Supabase`) are Deluge scripts attached to CRM workflow rules. |
| **LLP** | Limited Liability Partnership — the legal entity that owns a farm project. Each LLP record in Zoho's `LLP_Creation_Module` maps to one row in `public.llps` and (by default) one row in `public.projects`. |
| **CRM v3** | Zoho CRM REST API v3 (the one we call from `zoho-reconcile-daily`). Endpoint base: `https://www.zohoapis.in/crm/v3`. |
| **RLS** | Row-Level Security. Postgres policies that restrict which rows `authenticated` (i.e. the Flutter app) can read/write. Service-role (the Edge Functions) bypasses RLS. Defined in migrations `009`, `017-021`. |
| **SBP-prefixed token** | Supabase personal access tokens. Look like `sbp_<base64>`. Required for `supabase functions deploy`. Mint at <https://supabase.com/dashboard/account/tokens>. Distinct from the per-project anon/service-role keys. |
| **Vault** | Supabase's encrypted secret store (`vault.secrets` + `vault.decrypted_secrets` view). Backed by Postgres. The `cron_secret` entry is read by pg_cron at run time to call our Edge Functions. |
| **Edge Function** | A Deno-runtime serverless function deployed to Supabase. Lives under `supabase/functions/<name>/index.ts`. URL pattern: `https://<project>.supabase.co/functions/v1/<name>`. |
| **Idempotency key** | `webhook_log.idempotency_key` UNIQUE column. Format: `${module}_${recordId}_${modifiedTime}` for webhooks, `${zohoAllocationId}_payout_${i}` for payouts. Re-deliveries of the same key short-circuit to `{status:"duplicate"}`. |
| **Stale-write guard** | The `if (incomingUpdated <= cur.updated_at) return;` check in `handleContact`. Defends against out-of-order Zoho deliveries clobbering newer state. |
| **Cold-start lookback** | `COLD_START_LOOKBACK_MS = 25h` in the reconcile function — the minimum window pulled on every run, regardless of `max(last_synced_at)`. Covers single missed daily run + clock skew. |
| **Default project** | "The first project under an LLP (by `updated_at ASC`)" — created automatically by `handleProject` on first sync, with `projects.id = llps.id`. Subsequent projects under the same LLP are added manually in Studio. |

---

## See also

- `docs/data_flow_guide.md` — the architecture, schema, and field
  reference companion to this doc. If you need to know *what* a
  column means or where it comes from in CRM, start there.
- `supabase/migrations/20260507120000_023_last_synced_at_columns.sql`
  — defines `sync_status` view and `sync_alerts` table.
- `supabase/migrations/20260507120100_024_schedule_reconcile_and_alert.sql`
  — defines the pg_cron schedules.
- `docs/testing/runs/2026-05-08-deploy.log` — example deploy log
  showing typical CLI output (and the `db push` password-auth
  failure pattern you'll likely also hit).

---

## Common errors (2026-05-11 additions)

### `Email "...@arl.test" is invalid` (onboard-investor 500)

- **Symptom.** `POST /functions/v1/onboard-investor` returns
  `{"error":"invite failed","detail":"Email address \"<addr>\" is invalid"}`.
- **Cause.** Supabase Auth rejects RFC 6761 reserved TLDs (`.test`,
  `.example`, `.invalid`, `.localhost`). Comes from
  `supabase.auth.admin.inviteUserByEmail` (DEF-2026-05-11-02).
- **Fix.** Use a real domain. For UAT fixtures, `@agresearchlabs.com`
  (or any owned domain) is fine — the mailbox doesn't need to exist;
  inviteUserByEmail still creates the auth.users row, and the magic-
  link email simply bounces with no impact on the row's lifecycle.

### CRM record exists in Zoho but never lands in Supabase

- **Symptom.** `select … from webhook_log where zoho_record_id = '…'`
  returns 0 rows after a programmatic create against the Zoho CRM API.
- **Cause.** Zoho's `createRecords` API does **not** auto-fire workflow
  rules. The "Supabase Sync" workflow on a module is only triggered
  when (a) a UI create/edit happens, or (b) the API request includes
  `trigger: ["workflow"]` in the body (DEF-2026-05-11-03). MCP and
  REST callers skip the workflow by default.
- **Diagnosis.**
  1. `select * from webhook_log where zoho_record_id = '<id>' order by received_at desc limit 5;`
  2. If empty → workflow didn't fire. Confirm the rule exists + is active
     in Zoho Setup → Automation → Workflow Rules.
  3. If you see a row with `status=failed`, that's a different problem;
     read `error_message`.
- **Fix.**
  - For ad-hoc one-off: fire the webhook directly with the payload
    Deluge would have sent (see `docs/testing/fixtures/fixture_payloads.json`).
  - For repeatable scripts: include `trigger: ["workflow"]` in every
    `createRecords` / `updateRecord` body. Example:
    `body: { data: [...], trigger: ["workflow"] }`.
  - Otherwise wait for `zoho-reconcile-daily` (01:00 UTC) to catch up
    — it pulls all modified records since the last successful run and
    upserts them. Worst-case lag is one cron interval (~24h).

### Zoho `MANDATORY_NOT_FOUND` on `LLP_UnitAllocation_Module` create

- **Symptom.** `createRecords` returns:
  `{"code":"MANDATORY_NOT_FOUND","details":{"api_name":"Name","json_path":"$.data[0].Name"},"message":"required field not found","status":"error"}`.
- **Cause.** `LLP_UnitAllocation_Module.Name` is a required field on
  the Zoho module. The UI auto-generates via auto-number; the API
  doesn't (DEF-2026-05-11-04).
- **Fix.** Always include `Name` in the create payload. Naming
  convention used so far: `UAT-<YYYY-MM-DD>-<n>` for fixtures,
  `<arl_id>-<short_llp>-<seq>` for production allocations. The
  webhook handler doesn't care about the value; it's purely a Zoho
  display field.

### `duplicate key value violates unique constraint "investors_zoho_contact_id_unique"` (or `_key`)

- **Symptom.** `onboard-investor` returns 500 with Postgres `23505`,
  or a direct INSERT/UPDATE on `investors` rejects.
- **Cause.** Two attempts to link an `investors` row to the same
  `zoho_contact_id`. The partial UNIQUE constraint (migration 025,
  closes DEF-2026-05-11-05) blocks this so we don't end up with two
  app accounts pointing at the same CRM Contact.
- **Diagnosis.** Find the existing row:
  `select id, email, name, arl_id, onboarded_at from investors where zoho_contact_id = '<id>';`
- **Fix.** Don't re-onboard; reuse the existing `investor_id`. If the
  original onboard was wrong (e.g. wrong email), edit that row in
  Studio rather than creating a second.
