# Sync Runbook — push -demo fixtures into Supabase

**Owner:** ARL Tech
**Companion to:** `sync_fixtures.py`, `fixture_payloads.json`, `CRM_SCHEMA_NOTES.md`

This runbook walks you through pushing the 19 `-demo` records that already exist in Zoho CRM into Supabase. It exists because the Zoho workflow rule that should auto-fire `zoho-crm-webhook` did not fire for our API-created records, so we use the manual `crm-resync` and `onboard-investor` paths instead.

---

## Quick reference

| Item | Value |
|---|---|
| Supabase project | `oynfhdqizebvgmaoiuax` (Growize Main DB) |
| Region | ap-south-1 |
| onboard-investor URL | `https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/onboard-investor` |
| crm-resync URL | `https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/crm-resync` |
| Fixture count | 7 contacts + 5 LLPs + 7 allocations = 19 records |

---

## Step 0 — Prerequisites

You need both Supabase secrets:

- `ADMIN_SECRET` — for `onboard-investor`. Set via `supabase secrets set ADMIN_SECRET=<value>`.
- `ADMIN_RESYNC_SECRET` — for `crm-resync`. Set via `supabase secrets set ADMIN_RESYNC_SECRET=<value>`.

To **read** what they are set to (you cannot — Supabase doesn't expose secret values once set), you have two choices:

1. **Find the value where you stored it locally** (password manager, secure note, the original `supabase secrets set` command).
2. **Rotate**: generate a new secret, run `supabase secrets set ADMIN_SECRET=<newvalue>` and `supabase secrets set ADMIN_RESYNC_SECRET=<newvalue>` from the repo root, then use the new values here. Rotation is fine — both secrets are server-only and the only thing that knows them today are: (a) Supabase env, (b) Zoho workflow's outbound HTTP request configuration (for WEBHOOK_SECRET, NOT for ADMIN_*).

> **WEBHOOK_SECRET is unrelated** — it's used by `zoho-crm-webhook`, not by either of our two functions. Don't confuse them.

---

## Step 1 — Create `.env.local`

In the same directory as `sync_fixtures.py` (i.e., `docs/testing/fixtures/`), create a file named `.env.local`:

```bash
# .env.local — DO NOT COMMIT (already in .gitignore via .claude/ pattern, verify before saving)

SUPABASE_URL=https://oynfhdqizebvgmaoiuax.supabase.co
ADMIN_SECRET=<paste onboard-investor secret here>
ADMIN_RESYNC_SECRET=<paste crm-resync secret here>
```

Verify it's gitignored:

```powershell
git check-ignore docs/testing/fixtures/.env.local
# Should print the path. If it doesn't, add it to .gitignore.
```

---

## Step 2 — Dry run first

```powershell
cd docs/testing/fixtures
python3 sync_fixtures.py --dry-run
```

Expected output (excerpt):

```
[2026-05-05T22:30:01] LOG: sync_run_20260505_223001.log
[2026-05-05T22:30:01] SUPABASE_URL = https://oynfhdqizebvgmaoiuax.supabase.co
[2026-05-05T22:30:01] ADMIN_SECRET set:        True
[2026-05-05T22:30:01] ADMIN_RESYNC_SECRET set: True
[2026-05-05T22:30:01] DRY RUN: True

── PHASE 1: onboard-investor — 7 contacts ──
  → F-INV-01 sahilmhl25+demo-aarav@gmail.com
    status=200 resp={"dry_run": true}
  ...

──────  SUMMARY ──────
  investors      OK=7  FAIL=0
  llps           OK=5  FAIL=0
  allocations    OK=7  FAIL=0
```

If the dry-run looks right, proceed.

---

## Step 3 — Real run

```powershell
python3 sync_fixtures.py
```

The script:
- Calls `onboard-investor` 7 times (creates 7 auth users + investors rows + sends 7 password-setup emails).
- Calls `crm-resync` 5 times for LLPs (upserts `llps` + 1 `projects` row each).
- Calls `crm-resync` 7 times for Allocations (upserts `investor_units`, plus payouts derived from Amount_1/UTR_1/Date_1).

Total wall time ≈ 12 seconds (with 0.5s pacing between calls).

**Expected mailbox state for `sahilmhl25@gmail.com`:** 7 password-setup emails arrive (one per `+`-alias). All hit the same inbox. You can leave them unopened — fixtures don't need the password set yet.

---

## Step 4 — Verify

The script prints verification SQL at the end. Copy-paste into the Supabase SQL editor:

[Supabase SQL editor (project Growize Main DB)](https://supabase.com/dashboard/project/oynfhdqizebvgmaoiuax/sql)

Expected counts:

| Query | Expected |
|---|---|
| investors WHERE email LIKE 'sahilmhl25+demo-%' | 7 |
| llps WHERE name LIKE '%-demo' | 5 |
| projects WHERE name LIKE '%-demo' | 5 |
| investor_units WHERE zoho_allocation_id LIKE '11691010000014%' | 7 |
| payouts WHERE utr LIKE 'DEMOUTR%' | 5 (Amount_1 was set on F-ALC-01/02/04/05/06/EXIT — six records — but the webhook handler skips entries without a UTR, so verify count) |
| webhook_log source=manual_resync | 12 (5 LLP + 7 alloc events) |

If any count is off, open the run log (`sync_run_*.log`) and look at the response bodies.

---

## Step 5 — Update Fixture Spec sheet

After verification passes, the **Verified in Supabase** column on the `Fixture Spec` sheet of `ARL_Test_Tracker.xlsx` should flip from `No` to `Yes` for the 19 rows. The script doesn't update the xlsx automatically — it's a manual step (or run a small follow-up script).

Quick way: with verification SQL passing, just bulk-set column F to `Yes` for rows 5..25.

---

## Troubleshooting

### `unauthorized` from onboard-investor or crm-resync

Wrong secret. Re-check with:

```powershell
supabase secrets list --project-ref oynfhdqizebvgmaoiuax
```

Then re-set if needed:

```powershell
supabase secrets set ADMIN_SECRET=<new> --project-ref oynfhdqizebvgmaoiuax
```

Update `.env.local` and re-run.

### `investor already exists` from onboard-investor

Means the email is already in `investors` — possibly from a previous partial run. Either:
- Delete the existing investor + auth user via Supabase dashboard, then re-run.
- Or skip phase 1 with `--only llps` followed by `--only allocations`.

### `investor not found for zoho_contact_id ...` from crm-resync allocation

Phase 1 didn't run, or the matching investor row was never created. Run `--only investors` first.

### `llp not found for zoho_llp_id ...` from crm-resync allocation

Phase 2 didn't complete. Run `--only llps` then `--only allocations`.

### Workflow trigger silently corrupts data on re-save

If the LLP record's `Total_Units` reverts to 1 again (the trigger we documented in `CRM_SCHEMA_NOTES.md`), it means saving the record from a different angle re-triggered the workflow. The fix is in CRM, not here. If this happens to fixture data, delete the affected LLP records in Zoho and re-create with the 2-step pattern (bare create → update without `Total_Project_Cost`).

### Run log shows `status=0`

Network issue — script couldn't reach the URL. Check VPN, DNS, or whether you have outbound HTTPS to `*.supabase.co`.

---

## Re-running

The script is idempotent on the Supabase side because all upserts use `zoho_*_id` as the conflict key. Onboarding will fail with 409 for already-onboarded investors — that's expected, just means re-runs only fix the gaps.

To start fresh (rare, only for cleanup):

1. SQL: `DELETE FROM payouts WHERE utr LIKE 'DEMOUTR%';`
2. SQL: `DELETE FROM investor_units WHERE zoho_allocation_id LIKE '11691010000014%';`
3. SQL: `DELETE FROM projects WHERE name LIKE '%-demo';`
4. SQL: `DELETE FROM llps WHERE name LIKE '%-demo';`
5. Supabase Auth dashboard: delete the 7 auth users with `sahilmhl25+demo-*@gmail.com`.
6. SQL: `DELETE FROM investors WHERE email LIKE 'sahilmhl25+demo-%';`
7. Re-run `python3 sync_fixtures.py`.

The CRM records stay untouched — they're the source of truth.

---

## What to do AFTER this runbook

1. **Update Fixture Spec sheet.** Mark `Verified in Supabase = Yes` for all 19 rows.
2. **Investigate why the Zoho workflow rule didn't fire.** Open the workflow in Zoho UI, inspect the trigger conditions. This is a real production risk — if records get edited without firing the workflow, Supabase silently goes stale.
3. **Start running the test cases.** With fixtures in Supabase, the `Test Cases` sheet of `ARL_Test_Tracker.xlsx` is now executable. Pick `SC-ALC-001` first (Paid + Active scenario) — it's the canary for the whole flow.
4. **Set up the Daily UAT schedule.** Per `DAILY_UAT_RUNBOOK.md` — 18 cases run automatically each morning.
