# Zoho Workflow Rule — Fix Runbook

**Owner:** ARL Tech (you)
**Estimated time:** 10–15 min in the Zoho UI
**Why this exists:** Our 19 `-demo` records were created via the Zoho API (MCP) and silently did NOT trigger the workflow rule that calls `zoho-crm-webhook`. As a result, none of them appeared in Supabase. **This is a production risk** — if the same condition skips real records (admins editing via API, batch imports, future tooling), Supabase data goes stale without anyone noticing.

This runbook walks you through:
1. Inspecting the 3 workflow rules to find the misconfiguration.
2. Most likely cause and the fix.
3. Verifying the fix with a known `-demo` record.

---

## What we observed

- `webhook_log` table has 31 rows total, all from real production saves between 2026-04-15 and 2026-04-29. The pipeline works.
- After 2026-04-29: zero webhook hits, including for our 19 API writes today.
- `crm-resync` exists as a manual override — telling us the team already knows the workflow can miss records.
- Even passing `trigger: ["workflow"]` in the API call didn't fire the webhook for our records. So it's not the API client suppressing workflows — it's the workflow rule's own filter rejecting the records.

## Most likely causes (in order of likelihood)

1. **Workflow rule's filter condition excludes our records.** Example: "Only fire when `KYC` field changes" — our demo Contacts have no KYC. Or "Only fire when `LLP_Status` changes from one specific value" — our LLPs went straight to a state the rule doesn't watch.
2. **"Execute on" trigger is too narrow.** Zoho lets you choose: Create / Edit / Field Update / Record Action / Delete. If only "Field Update" is set with a specific field, generic creates won't trigger it.
3. **Workflow rule was disabled or deleted recently** (last successful webhook was 2026-04-29, and a code update happened on 2026-04-30 per `crm-resync.created_at = 1777496349 = 2026-04-29 16:59 UTC`). Maybe whoever added `crm-resync` also disabled the rule by accident.
4. **Webhook secret mismatch.** Zoho silently fails the outbound call when the function returns 401. Check if `WEBHOOK_SECRET` was rotated.

---

## Step 1 — Open the Zoho workflow rules page

Login as admin → **Setup → Automation → Workflow Rules**

URL pattern (Zoho India): `https://crm.zoho.in/crm/org<ORG_ID>/setup/automation/workflow-rules`
(Your org_id is `60061770791`.)

You should see a list of workflow rules. Look for ones targeting:

- `Contacts`
- `LLP_Creation_Module` (display name: "LLP Creation Module")
- `LLP_UnitAllocation_Module` (display name: "LLP UnitAllocation Module")

If they exist, they're probably named something like "Sync Contact to Supabase", "Push LLP changes to App", etc.

**Record what you find:**

| Module | Rule name | Status (Active/Inactive) | Notes |
|---|---|---|---|
| Contacts | | | |
| LLP_Creation_Module | | | |
| LLP_UnitAllocation_Module | | | |

If any rule is **missing or Inactive**, that's likely the issue. Re-create or re-activate.

---

## Step 2 — Inspect each rule's trigger conditions

For each rule, click into it and check four things:

### 2a. Execute on

Should be **all of**:
- Create
- Edit  *(or "Field Update" with no specific field — i.e., any update)*

If "Field Update" is set with a specific field, change to plain Edit (or add Create as a separate trigger).

### 2b. Filter / criteria

Look at the **"Which records would you like to apply the rule to?"** section.

Ideally it should be **All Records** (no filter). If there's a filter:

- "When KYC = 'Completed'" — too restrictive, will miss new records.
- "When Modified by = <specific user>" — will miss API writes by service users.
- "When some field is not empty" — will miss bare creates (which is exactly our 2-step pattern).

**Recommended filter:** none, or at most "Name does not start with [system prefix]" if you want to exclude bots.

### 2c. Actions

Should have a **Webhooks** action that POSTs to `https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/zoho-crm-webhook` with:
- Method: POST
- Body type: JSON
- Custom header: `X-ARL-Webhook-Secret: <secret value>`
- Body: maps Zoho fields to a JSON payload like `{ "module": "Contacts", "operation": "create", "data": { "id": "${id}", "First_Name": "${First_Name}", ... } }`

If the webhook URL is wrong, or the secret header is missing, calls will silently 401.

### 2d. Test it

In the rule edit screen, Zoho usually has a **"Test webhook"** or **"Preview"** button. Run it. If it returns 401 → secret mismatch. If 500 → the function received the call but threw — check `webhook_log` in Supabase for the failed entry.

---

## Step 3 — Verify by re-saving F-LLP-A

After making any changes, re-save one of our records to confirm the webhook fires:

**In Zoho UI:**

1. Navigate to LLP Creation Module → search for "Alpha Mango LLP-demo" (id `1169101000001433001`).
2. Open the record → click any field → click Save (no need to change anything; just trigger an Edit event).

**In Supabase:**

Run this query immediately after (within 30s):

```sql
SELECT event_type, status, received_at, error_message
FROM webhook_log
WHERE zoho_record_id = '1169101000001433001'
ORDER BY received_at DESC
LIMIT 5;
```

**Expected:** one new row with `event_type = 'LLP_Creation_Module.update'`, `status = 'processed'`.

**If status = 'failed':** read `error_message` and fix accordingly. Common ones:
- `llps upsert failed: ...` — Supabase schema problem, check migrations.
- nothing returned (still empty result) — webhook still not firing; revisit Step 2.

---

## Step 4 — If everything is wired correctly but still no webhook…

This sometimes happens with Zoho when API writes don't share the workflow context correctly. Workarounds:

### Workaround A — Add a "Schedule" trigger fallback

Zoho lets you schedule a workflow to run every 1 hour and process records modified in the last interval. Less responsive, but catches everything regardless of the originating channel.

### Workaround B — Use a Custom Function instead of Webhook

A Zoho Custom Function (Deluge script) running on Create/Edit can call Supabase via `invokeUrl` and is more reliable than the Webhook action for API-originated saves.

### Workaround C — Cron-based pull from Zoho

The `crm-resync` function already does this on demand. We could add a Supabase scheduled job (`pg_cron`) that calls Zoho's API every N minutes, finds modified records, and runs them through the same upsert logic.

**Lowest-effort recommendation: Workaround A.** Set the schedule trigger to 15 min and you have a worst-case staleness budget.

---

## Step 5 — Once fixed, backfill our 19 records

Either:

**Option 1 — Re-save each in Zoho UI.** 19 clicks. Tedious but verifies the fix end-to-end.

**Option 2 — Run our `sync_fixtures.py` script** with the secrets to push them via `crm-resync`. This is the manual-override path.

Either works. After backfill, run the same verification query as Step 3 but for all 19 ids:

```sql
SELECT zoho_record_id, event_type, status, received_at
FROM webhook_log
WHERE zoho_record_id IN (
  '1169101000001433001','1169101000001433016','1169101000001433017',
  '1169101000001439003','1169101000001433018','1169101000001467016',
  '1169101000001467017','1169101000001467018','1169101000001467019',
  '1169101000001467020','1169101000001467021','1169101000001467022',
  '1169101000001466002','1169101000001430008','1169101000001430009',
  '1169101000001430010','1169101000001430011','1169101000001430012',
  '1169101000001430013'
)
ORDER BY received_at DESC;
```

Expected: 19 rows, all `status = 'processed'`.

---

## Step 6 — Add a regression test to Daily UAT

Add a new daily case to `DAILY_UAT_RUNBOOK.md`:

> **D-19 — Workflow firing canary.** The agent updates `LLP_Owner` field on F-LLP-A via API (small no-op-style change), waits 60 seconds, then queries `webhook_log` for the corresponding entry. Failure means the workflow is silently broken again. This is the early-warning system — without this case, we won't know workflows died until users notice stale data.

This is the single most valuable monitoring case to add for production.

---

## Then proceed to UI testing

Once webhooks fire and Supabase has all 19 records, the path is clear:

1. Investor logs into the Flutter app (using one of `sahilmhl25+demo-*@gmail.com`).
2. Browser-agent MCP clicks through the screens (Home, Projects, Project Detail, Financials, Documents, Exit).
3. Verify each scenario from `SCENARIOS.md` renders correctly.

That's the original plan — and now it's actually executable end-to-end.

---

## Findings to record

After investigation, document what you found in `BACKLOG.md` or as a decision file:

- Which workflow rule had which misconfiguration
- What the fix was
- Whether other CRM workflows might have the same issue (e.g., the field-corrupting trigger from `CRM_SCHEMA_NOTES.md` may be related — both might have been auto-generated by the LLM-via-MCP setup)
- Recommendation for whether to add D-19 to the daily UAT
