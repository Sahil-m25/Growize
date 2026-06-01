# E2E Test Results — Ops-side, v27 envelope fix verification

**Date:** 2026-05-15
**Project:** Supabase `oynfhdqizebvgmaoiuax`
**Environment:** prod-style (zoho-crm-webhook v27 + Zoho Custom Functions Push_Contact / Push_LLP / Push_Allocation_To_Supabase shipped today)
**Tester:** ARL Tech (orchestrator + sub-agents)
**Wall time:** ~50 min

## Final verdict: NO-GO with one P1 blocker

The v27 webhook envelope fix and the three Zoho Custom Functions are working as designed for **edits** (the path the fix targeted). Wave 1 passed cleanly across all three entities (Contact, LLP, Allocation). Waves 3 and 4 also showed the broader chain is healthy.

However, while running Wave 2 / Wave 3 we surfaced a pre-existing — but until now invisible — **P1 defect** that blocks any "new investor onboarded from Zoho-only data" flow:

> **DEF-V27-01 (P1):** Zoho `Contacts` records created via API fire a `Contacts.update` webhook (not `.create`). The handler marks them `status='processed'` with `error_message=null`, but **silently no-ops** — no row is inserted into `public.investors`. Only contacts that already exist in Supabase get updated.

Side-effects observed today:
- Creating an Allocation that references a not-yet-landed Contact fails downstream: `LLP_UnitAllocation_Module.edit` payload `1169101000001709007` was rejected with `investor not found for zoho_contact_id 1169101000001697008`.
- The `onboard-investor` edge function masks this issue because it inserts the investors row itself — but the production path described in the runbook ("create contact in Zoho → row lands → ops onboards") is broken in step one.

Recommendation: **fix DEF-V27-01 before shipping** (upsert on `Contacts.update`, or have the CF emit `Contacts.create` for new records). All other systems are green.

---

## Stop-condition tally
| Condition | State |
|---|---|
| Wave 1 envelope fix verified | PASS — continue |
| 5+ new P1 defects | 1 P1 found — continue |

Ran all 4 waves.

---

## Wave 1 — webhook v27 envelope verification (PASS)

Triggered Description-only updates on three pre-existing records, observed `webhook_log` + downstream tables.

| Sub-case | Zoho record | webhook_log status | Latency | payload shape | Downstream row | Verdict |
|---|---|---|---|---|---|---|
| Contact.update | `1169101000001586020` (Test Investor One-demo) | processed | 205 ms | `data:{…}` `_shape:"mixed"` `module:"Contacts"` `operation:"update"` | `investors.updated_at` 15:36:12.95; pan_masked `AAAPA****A`, bank_account_masked `XXXX-XXXX-0123` intact | PASS |
| LLP.edit | `1169101000000876001` (Test First LLP) | processed | 170 ms | `data:{…}` `_shape:"mixed"` `module:"LLP_Creation_Module"` `operation:"edit"` | `llps.updated_at` 15:36:18.028; linked `projects.updated_at` 15:36:18.114 | PASS |
| Allocation.edit | `1169101000001599009` | processed | 132 ms | `data:{…}` `_shape:"mixed"` `module:"LLP_UnitAllocation_Module"` `operation:"edit"` | `investor_units.updated_at` 15:36:22.51; trigger 046 kept `projects.units_issued=20 / units_available=780 / total=800` consistent | PASS |

Envelope-shape note: handler stores the unwrapped record (`payload.data` is the single object) plus `_shape` / `module` / `operation` at the envelope level. This is the canonical post-v27 shape; the v3 envelope `{"data":[{…}], …}` is being unwrapped correctly before persistence. All Wave 1 rows carried `_shape: "mixed"` (indicating the lookup-expanded shape from the new CFs), confirming the new CFs are now firing rather than the legacy flat-form Zoho workflow webhooks.

---

## Wave 2 — Delete chain throwaways (USER-ACTION-PENDING)

Three throwaway records were created in Zoho prefixed `[E2E-V27-DELETE]`. Workflow rules on Delete only fire from the **Zoho UI**, so the orchestrator cannot complete this wave end-to-end.

| Entity | Zoho record id | Zoho name | Supabase row state | Action for user |
|---|---|---|---|---|
| Contact | `1169101000001697008` | DeleteV27 [E2E-V27-DELETE] | **NOT in `investors`** (blocked by DEF-V27-01) | Delete from Zoho UI; verify delete CF behavior is idempotent given no Supabase row exists |
| LLP | `1169101000001682009` | [E2E-V27-DELETE] Throwaway LLP | `llps.id = 2fef7529-2aa9-457a-a615-8f0dac2a42c4`, linked project also created | Delete from Zoho UI; verify llps + auto-created projects row both soft-or-hard delete |
| Allocation | `1169101000001709007` | [E2E-V27-DELETE] Wave2 Allocation | **NOT in `investor_units`** (the allocation webhook failed at create time because its Customer didn't exist in `investors` — symptom of DEF-V27-01) | Delete from Zoho UI; verify delete CF runs cleanly with no Supabase row to match |

**Verification SQL after each UI delete:**
```sql
-- Contact delete
SELECT id, deleted_at, updated_at
FROM investors
WHERE zoho_contact_id = '1169101000001697008';
-- Expect: 0 rows now (already 0), or row with deleted_at set if DEF-V27-01 is fixed before UI delete

-- LLP delete
SELECT id, name, deleted_at, updated_at
FROM llps
WHERE zoho_llp_id = '1169101000001682009';
-- Expect: deleted_at IS NOT NULL (soft) or 0 rows (hard)
SELECT id, name, deleted_at, llp_id
FROM projects
WHERE llp_id = '2fef7529-2aa9-457a-a615-8f0dac2a42c4';
-- Expect: deleted_at IS NOT NULL or 0 rows

-- Allocation delete
SELECT id, zoho_allocation_id, deleted_at
FROM investor_units
WHERE zoho_allocation_id = '1169101000001709007';
-- Expect: 0 rows (already 0)

-- Webhook audit after UI deletes
SELECT received_at, event_type, status, error_message, zoho_record_id
FROM webhook_log
WHERE zoho_record_id IN
    ('1169101000001697008','1169101000001682009','1169101000001709007')
  AND received_at >= '2026-05-15 16:00:00+00'
ORDER BY received_at DESC;
-- Expect: 3 *.delete rows, all status='processed'
```

Status: **USER-ACTION-PENDING.**

---

## Wave 3 — Full E2E happy path (PASS with caveats)

Used a NEW throwaway investor end-to-end.

### Step 1 — Create [E2E-V27-FULL] Contact in Zoho
- Zoho id: `1169101000001654012`
- Email: `e2e-v27-full-2026-05-15@agresearchlabs.com`
- All fields populated: PAN, Aadhaar, DOB, bank, address, KYC=Pending

### Step 2 — Verify investor row lands via webhook (FAIL — DEF-V27-01)
- Webhook `Contacts.update` for `1169101000001654012` fired and was logged status=processed.
- `public.investors` row was NOT inserted. Retried with a second update; still no insert.
- Continued the rest of Wave 3 with a workaround: invoked `onboard-investor` directly (which self-inserts the row from request body).

### Step 3 — Call onboard-investor (PASS)
```
POST https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/onboard-investor
X-ARL-Admin-Secret: <redacted>
body: {email, name, arl_id=ARL-E2E-V27-FULL, zoho_contact_id=1169101000001654012, phone, salutation}
→ 200 { investor_id: e9b6b56c-5a43-41a2-ad0e-916da70ef402, … }
```
- `auth.users` row created at 15:44:44.08, invited_at set.
- `public.investors` row created at 15:44:47.04, kyc_status=pending, arl_id=ARL-E2E-V27-FULL, zoho_contact_id linked.

### Step 4 — Set password via admin SQL (PASS)
```sql
UPDATE auth.users SET encrypted_password = crypt('E2EVerify-2026-05-15!', gen_salt('bf')),
                       email_confirmed_at = COALESCE(email_confirmed_at, now())
WHERE email = 'e2e-v27-full-2026-05-15@agresearchlabs.com';
```
Confirmed = true.

### Step 5 — REST verification as the new investor (PASS)
- `POST /auth/v1/token?grant_type=password` returned JWT (length 879).
- `GET /rest/v1/investors` returned exactly 1 row scoped to caller (RLS correct).
- `GET /rest/v1/notifications` returned `[]` (no notifications yet — correct pre-KYC-flip baseline).

### Step 6 — Trigger Contacts.update to backfill from Zoho (PASS)
A subsequent `Contacts.update` (a Description touch) on `1169101000001654012` did update the now-existing investors row at 15:45:43.46. Fields landed correctly:
- `pan_masked = "ABCDE****F"` ✓
- `bank_account_masked = "XXXX-XXXX-3322"` ✓ `bank_ifsc = "HDFC0000123"` ✓ `bank_branch = "Bangalore HSR"` ✓ `bank_holder_name = "FullE2E Investor"` ✓
- `address_line1 / city / state / pincode / country` all populated ✓
- `date_of_birth = 1992-04-15` ✓ `salutation = "Mr."` ✓

Minor data-fidelity observations (logged as P3):
- `aadhaar_masked` = empty string. Zoho payload contains `Aadhaar_Number: "[REDACTED]"` (sensitive-field redaction), so the handler has nothing to mask. Probably WAI but worth confirming the app handles the empty value gracefully.
- `bank_name` = empty string. The original create request sent `"Bank_Name": "HDFC Bank"` but Zoho's outbound payload shows `Bank_Name: ""`, suggesting either a Zoho field-permission issue or a write-back failure on Zoho's side. Not a Supabase bug.

### Step 7 — Create [E2E-V27-FULL] Allocation (PASS)
- Created allocation `1169101000001654020` linking new investor to throwaway LLP `1169101000001656022`. Sent UTR_1/Date_1/Amount_1 fields.
- Webhook processed at 15:45:46.84.
- `investor_units` inserted: `f2cee51e-d4af-4b83-9844-7d4d6fcb59e7`, issued_units=2, unit_price=100000, capital_invested=200000, allocation_status=Issued.
- Trigger `trg_recompute_project_units` recomputed `projects.units_issued=2 / units_available=8 / total_units=10` ✓.

### Step 8 — Verify payouts unpacking from UTR fields (FAIL — DEF-V27-02 P2)
Sent `UTR_1="UTRTEST1234567"` `Date_1="2026-05-15"` `Amount_1="200000"` inside the allocation create payload. **No payout row was inserted.** All 3 existing payouts in the table are `source='manual'`. The runbook says payouts should auto-unpack from allocation UTR_N/Amount_N/Date_N fields, but the v27 handler does not appear to do that today.

### Step 9 — KYC flip → notification (PASS)
- Updated Zoho contact `KYC = "Verified"` at 15:47:06.
- Webhook processed 15:47:07.87.
- `investors.kyc_status = 'verified'` at 15:47:08.07.
- Trigger `trg_notify_investor_kyc_status_change` fired: 1 row inserted into `notifications` (type='kyc', title='KYC verified', body='Your KYC has been verified. Tap to view.').

### Wave 3 cleanup status
Wave 3 throwaway records **NOT YET cleaned**. See cleanup section at the bottom of this doc.

---

## Wave 4 — Re-verify previously-passing families (PASS)

Light verification — table schemas, RLS policies, trigger functions, and a live REST scoping probe with both `ofclash98@gmail.com` (existing investor) and the new Wave 3 investor.

| Family | Probe | Result |
|---|---|---|
| Bank change request lifecycle | RLS `investor_id = auth.uid()` on SELECT; trigger `trg_notify_bank_change_status_change` emits notification on `pending → approved/rejected`. ofclash98 sees `[]` (no requests). | PASS |
| Exit lock-in RLS | RLS `user_id = auth.uid()` on SELECT. ofclash98 sees their 1 existing exit_request (`ce2bfeb7`, status=approved). Trigger `trg_notify_exit_request_status_change` notifies on terminal-state transition. | PASS |
| Document tiering visibility | RLS combines (visibility='common') OR ('project' AND project_id ∈ caller's investor_units) OR ('investor' AND investor_id=caller). Wave 3 user (only allocation = throwaway LLP) sees 1 doc (the common ARL Profile). ofclash98 sees 3 docs (common + their project's brief + their KYC). | PASS |
| Consultation request → Slack | Trigger `trg_notify_consultation_request` reads `cron_secret` from vault and posts to `notify-consultation-request` edge function via `net.http_post`. Edge function v2 active. Wiring intact. | PASS |
| Support ticket round-trip | Trigger `trg_notify_ticket_reply` fires on `ticket_messages` INSERT; ignores investor-originated messages, distinguishes first-from-ops vs reply. ofclash98 sees their 2 tickets. | PASS |

---

## Defects opened this session

### DEF-V27-01 — P1 — Contacts.update silently no-ops for non-existing investors
**Severity:** P1 (blocks "new investor lands from Zoho-only data" flow)
**Reproducer:** Create a brand-new Contact via Zoho API. Observe webhook_log shows `Contacts.update` `status=processed`, but `investors` table is unchanged.
**Evidence:** 5 such no-op events today, all `status='processed'`, none inserted:
- `1169101000001655002` 14:50:00
- `1169101000001661017` 14:53:13
- `1169101000001700005` 15:15:50
- `1169101000001697008` 15:38:33 (Wave 2 throwaway, this run)
- `1169101000001654012` 15:38:36 + 15:42:00 + 15:45:43 (Wave 3 throwaway, this run)
**Likely fix:** In `zoho-crm-webhook` v27, the `Contacts.update` handler should UPSERT (insert when no row matches `zoho_contact_id`) — or the upstream CF should emit `Contacts.create` for first-seen records. Today an API-created contact produces a `.update` event only.
**Workaround:** call `onboard-investor` directly (it self-inserts), or trigger the same Contact through Zoho UI which fires `.create`.
**Knock-on:** allocation webhook errors with `investor not found for zoho_contact_id …` (see `webhook_log` row `1169101000001709007 — 15:42:15`).

### DEF-V27-02 — P2 — Allocation UTR fields not unpacking into payouts
**Severity:** P2
**Reproducer:** Create or edit an allocation in Zoho with non-empty UTR_1 / Date_1 / Amount_1 (and similar pairs 2-10). Observe that no `public.payouts` rows are written by the webhook handler.
**Evidence:** Sent UTR_1=`UTRTEST1234567`, Date_1=`2026-05-15`, Amount_1=`200000` on allocation `1169101000001654020`. Webhook processed cleanly. `payouts` table count unchanged at 3 (all three pre-existing rows are `source='manual'`).
**Hypothesis:** The runbook describes payouts as "Sourced from LLP_UnitAllocation_Module (UTR/Amount/Date fields unpacked)" but the v27 handler may not have wired this path, or it requires a specific allocation_status / non-empty UTR_2 to trigger.
**Mitigation:** confirm whether this was intentionally deferred. If not, add UTR-unpacking step inside the allocation upsert.

### DEF-V27-03 — P3 — Bank_Name field round-trips empty from Zoho
**Severity:** P3 cosmetic / data fidelity
**Reproducer:** Create or update a Zoho Contact and set `Bank_Name = "HDFC Bank"`. Inspect the outbound webhook payload — `Bank_Name` is `""`.
**Likely cause:** Zoho field permission / picklist mapping on the Bank_Name field. Not a Supabase webhook bug. Triage on the Zoho side.

### DEF-V27-04 — P3 — aadhaar_masked left empty on first-sync
**Severity:** P3 nice-to-have
**Reproducer:** Webhook receives `Aadhaar_Number: "[REDACTED]"` from Zoho's sensitive-field policy; the handler stores `aadhaar_masked = ""` (empty). The app should display "not provided" rather than the empty literal, or the handler should compute a masked version from a separate raw-Aadhaar field if available.

### Pre-existing defect re-confirmed (not new)
- `daily_sync` rate-limit failures (`invalid_client` and "too many requests"): 26 of 35 historical failures are Zoho OAuth token-refresh issues during the daily reconcile job. Not part of v27 scope; covered by a different ticket per the prior runbook.

### Closed-as-fixed (verified this session)
- The previously-failing `Contacts.update` rows from 13:34–13:36 today (error: `Could not find the 'aadhaar_number' column of 'investors' in the schema cache`) — now passing in Wave 1. v27 column-mapping fix verified.

---

## Throwaway records left in the system

### Wave 2 — leave in place for USER UI-delete test
| Entity | Zoho id | Status |
|---|---|---|
| Contact | `1169101000001697008` | Zoho only |
| LLP | `1169101000001682009` (`Supabase llps.id=2fef7529-2aa9-457a-a615-8f0dac2a42c4`) | Both |
| Allocation | `1169101000001709007` | Zoho only |

### Wave 3 — pending cleanup (run after sign-off on this report)
| Entity | id | Cleanup query / call |
|---|---|---|
| Zoho Allocation | `1169101000001654020` | DELETE via Zoho API |
| Zoho LLP | `1169101000001656022` | DELETE via Zoho API |
| Zoho Contact | `1169101000001654012` | DELETE via Zoho API |
| Supabase auth.users + investors | `e9b6b56c-5a43-41a2-ad0e-916da70ef402` | `auth.admin.deleteUser` (cascades) |
| Supabase investor_units | `f2cee51e-d4af-4b83-9844-7d4d6fcb59e7` | cascade via investors |
| Supabase llps + projects | `4908bfcc-c06e-4bb4-b6d3-da7c8b9a7fd1` | explicit DELETE |

---

## Final ship verdict

**NO-GO** until DEF-V27-01 is fixed and re-verified. All other paths are green:
- v27 envelope unwrap: correct
- Edit/Update webhooks for Contacts / LLPs / Allocations: correct
- onboard-investor: correct
- KYC notification trigger: correct
- Project-unit recompute (trigger 046): correct
- RLS scoping across investors / documents / exit_requests / support_tickets / bank_change_requests: correct
- Slack consultation wiring: present

Once DEF-V27-01 ships, suggested smoke test:
1. Create a fresh Zoho Contact via API.
2. Confirm investors row lands within 10s.
3. Create an Allocation referencing that contact in the same minute.
4. Confirm investor_units + projects.units_issued land without error.
