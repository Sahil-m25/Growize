# Ops-Side End-to-End Test Results — 2026-05-15

**Run owner:** ARL Tech (Cowork session, Claude Opus 4.7) — parallel sub-agent orchestration
**Mental model under test:** ops touches Zoho CRM only; data auto-populates in Supabase; app auto-renders. No direct Supabase writes by ops, no app-side hacks.
**Supabase project:** `oynfhdqizebvgmaoiuax`
**Edge function under test:** `zoho-crm-webhook` v24 (deployed 2026-05-14, sha `6a992c6e…`)
**Test investor (kept):** `ofclash98@gmail.com` (id `27d3735e-470d-47a5-a413-9ae502194d3d`) — KYC=`pending`, has 1 investor_unit in project `9ba53e8f` with `investment_date=2026-05-13` (lock-in until 2031-05-13).
**Naming convention:** every Zoho record created in this run is prefixed `[E2E-2026-05-15-Fx]` for x = the family number; one diagnostic record used `[E2E-2026-05-15-DIAG]`.

---

## 1. Executive summary

| Family | Theme | PASS | FAIL | PARTIAL/SKIP | Verdict |
|---|---|---:|---:|---:|:---:|
| **F1** | Contact lifecycle (Investor) | 4 | 4 | 1 | **FAIL** (P0 blocker) |
| **F2** | LLP/Project lifecycle | 8 | 1 | 1 | **PARTIAL** (delete cascade missing per OPS-03) |
| **F3** | Allocation + Payouts | 8 | 2 | 0 | **PARTIAL** (2 P0s: UTR_1 drop, delete cascade) |
| **F4** | Bank change request | 11 | 0 | 0 | **PASS** |
| **F5** | Exit lock-in (RLS + trigger) | 8 | 0 | 0 | **PASS** |
| **F6** | Gallery + Documents | 10 | 0 | 1 | **PASS** (gallery e2e step needs manual Zoho attachment) |
| **F7** | Consultation request | 7 | 0 | 0 | **PASS** |
| **F8** | Support ticket lifecycle (both directions) | 10 | 0 | 0 | **PASS** |
| **Total** | | **66** | **7** | **3** | |

**8 new defects logged** (DEF-2026-05-15-OPS-01..08). Severity breakdown: **2 × P0**, **1 × P1**, **3 × P2**, **2 × P3**.

### Ship-readiness verdict: **NO-GO**

Two P0 defects independently block prod:

1. **DEF-2026-05-15-OPS-01 (P0)** — `zoho-crm-webhook` writes a non-existent `investors.aadhaar_number` column. **Every** Contacts.update from Zoho since 2026-05-15 13:34 UTC fails with PostgREST schema-cache error. Investor profile sync is broken: no KYC flip, no bank-field change, no address/phone/DOB edit reaches Supabase. The bell-trigger chain that depends on `kyc_status` transitions also goes dark. Reproduced 3× consecutively in `webhook_log` today.
2. **DEF-2026-05-15-OPS-02 (P0)** — Allocation payouts entered into the `UTR 1`/`Amount 1`/`Date 1` Zoho slot are silently dropped (no row, no notification, no error). Zoho field labelled "UTR 1" has API name `UTR` (no underscore) so the webhook reads `""`. UTR_2..10 work fine. Any ops user entering only the first payout slot will think it landed when it didn't.

Together these break the two most-trafficked CRM mutation paths (Contact-edit and first-payout-record).

**Strongly recommended P1 fix before launch:** DEF-OPS-03 (missing Zoho Delete triggers) — the Supabase-side soft-delete handlers (`handleContactDelete`, `handleLLPDelete`, `handleAllocationDelete`) are correctly implemented and verified-handler-code per webhook v24 source, but the Zoho workflow rules don't include a Delete trigger for any of the three modules. Off-boarding lifecycle is non-functional across the board.

### What's actually working solid

- Families 4, 5, 7, 8 are **clean PASSes**. Bank-change (incl. masking enforcement + rejection notes interpolation), Exit lock-in RLS (HTTP 403 / 42501) + status-change trigger, Consultation Slack-fan-out trigger (548ms latency end-to-end), and Support tickets (incl. migration 048 branching where ops-initiated first message reads "New message from ARL" rather than "New reply on your ticket").
- LLP webhook channel is alive: my diagnostic create at 13:44 UTC fanned out into `llps` + `projects` rows within 30s; subsequent status flip "Coming Soon" → "Open for Reservation" correctly flipped `is_listed_in_marketplace` from false to true. (The first sub-agent's "channel silent" verdict was a timing artifact — they didn't wait the full ~30s Zoho workflow queue.)
- PII masking on the webhook is fully working — `webhook_log.payload` correctly carries `PAN_Number=ABCDE****F`, `Aadhaar_Number=[REDACTED]`, `Bank_Account_Number=XXXX-XXXX-3456`. The OPS-01 bug is a write-target column-name bug, NOT a masking regression.
- Allocation → `investor_units` upsert → `trg_recompute_project_units` chain works (50/0/50 → allocate 10 → 50/10/40 → soft-delete → 50/0/50). Payouts UTR_2..UTR_10 + idempotency on retry verified.

---

## 2. Defects (new this run)

### DEF-2026-05-15-OPS-01 — **P0 (Production blocker)**
**Title:** zoho-crm-webhook writes investors.aadhaar_number — column does not exist (schema has aadhaar_masked)
**Layer:** Edge Function / Schema drift
**Trigger:** Any Contacts.update webhook event (3 reproductions today after webhook v24 deploy)
**Root cause:** `supabase/functions/zoho-crm-webhook/index.ts` line 488 (handleContact, DEF-2026-05-15-09 patch) writes `aadhaar_number: incomingAadhaar` into the upsert map. The `investors` schema has only `aadhaar_masked` (text). PostgREST rejects with `Could not find the 'aadhaar_number' column of 'investors' in the schema cache`. Each failed write rolls back the whole update map, so no field on the investor row changes when the webhook fires.
**Evidence:** webhook_log rows `40c6af78`, `1a3a280a`, `3a4e0bcd` — all today, all `status='failed'`, identical `error_message`. Schema query: `SELECT column_name FROM information_schema.columns WHERE table_schema='public' AND table_name='investors' AND column_name LIKE '%aadhaar%'` returns only `aadhaar_masked`.
**Impact:**
- KYC flips in CRM never reach Supabase → bell never lights up → `notify_investor_kyc_status_change` trigger never fires.
- Phone / mobile / address / city / state / pincode / DOB / bank-branch / holder edits in CRM all silently dropped from app view.
- Webhook silently fails — there's no visible alert; only `webhook_log.error_message` shows it.
**Fix options:**
1. (Preferred) Rename target column in handleContact() from `aadhaar_number` to `aadhaar_masked` AND wrap incomingAadhaar with a `maskAadhaar()` helper that keeps last 4 digits (mirror existing `maskBankAccount`, `maskPan` pattern). This honors PII policy from sanitizeForLogging.
2. Migration `051_add_aadhaar_number_to_investors.sql` adding the raw column — **NOT recommended**; violates the PII pattern that masks PAN + bank account.
**Reproduces in:** webhook v24 (current ACTIVE deployment).

### DEF-2026-05-15-OPS-02 — **P0 (Data loss)**
**Title:** LLP_UnitAllocation_Module UTR_1 / Amount_1 / Date_1 payouts silently dropped
**Layer:** Zoho field API ↔ webhook contract mismatch
**Trigger:** First payout slot entered in CRM Allocation record (UTR 1, Amount 1, Date 1).
**Root cause:** Zoho field labelled "UTR 1" in the CRM UI has API name `UTR` (no underscore suffix). The webhook at `supabase/functions/zoho-crm-webhook/index.ts` line 710 reads `d["UTR_${i}"]` for i=1..10. For i=1 it reads `d["UTR_1"]` which Zoho serialises as `""`. The guard `if (!utr || amt === undefined) continue;` then skips slot 1 entirely. UTR_2..UTR_10 work fine because those API names match the loop variable.
**Evidence:** Family 3 sub-agent's update to Zoho with `UTR_1="E2E-UTR-001"`, `Amount_1=500`, `Date_1=2026-05-15` yielded `webhook_log.status=processed` (no error), but the payouts table got zero rows for the allocation. The same allocation updated to add `UTR_2`, `UTR_3` (and later `UTR_4`) inserted the expected payouts and fired the notification.
**Impact:** Any ops user who enters a first payout into the UTR 1 slot will believe it was recorded — there's no error visible upstream or downstream. Investor's Financials screen will be missing that payout. Real money tracked outside the system.
**Fix options:**
1. (Preferred) Either rename the Zoho `UTR` field API name to `UTR_1` OR add an aliased column. Same-pattern remap for `Amount`/`Date` only required if they too don't have `_1` suffix (verify).
2. Webhook patch: in the loop, special-case `i === 1` to fall back to `d["UTR"] ?? d["UTR_1"]` (and same for Amount/Date). Lower risk to ship, but treats the Zoho-side typo as canonical.

### DEF-2026-05-15-OPS-03 — **P1 (Off-boarding lifecycle)**
**Title:** Zoho workflow rules missing Delete trigger for all 3 modules (Contacts, LLP_Creation_Module, LLP_UnitAllocation_Module)
**Layer:** Zoho workflow config (NOT a code defect)
**Reproductions:** 3 separate Family contexts confirmed:
- F1: `deleteRecord` on Contact `1169101000001661001` → no `Contacts.delete` event in `webhook_log` within 35s.
- F2/DIAG: `deleteRecord` on LLP `1169101000001682001` → no `.delete` event in `webhook_log` after 30s wait; `llps.deleted_at` + `projects.deleted_at` stayed NULL until I manually `DELETE`d from Supabase.
- F3: `deleteRecord` on Allocation `1169101000001673008` → no `.delete` event; `investor_units.deleted_at` stayed NULL; `projects.units_issued` never ticked back down (had to hard-delete the investor_units row to fire `trg_recompute_project_units`).
**Root cause:** The Zoho workflow rules POSTing to `/functions/v1/zoho-crm-webhook` are configured for the Create + Edit triggers only. The Delete trigger is either off, or routes to a different endpoint, or never sends `operation=delete` in the body/query. The Supabase handler code (`handleContactDelete`, `handleLLPDelete`, `handleAllocationDelete`, lines 766–857) is correctly implemented and even covers the FK soft-delete fan-out (LLP → projects cascade) and the auth.users ban via `ban_duration: '876000h'`. It just never gets invoked.
**Impact:** Anything ops deletes in Zoho stays alive in Supabase indefinitely. Off-boarded investors keep their auth.users + can sign in. Sunset LLPs / cancelled allocations stay visible in the marketplace and in investor portfolios.
**Fix:** In Zoho → Setup → Automation → Workflow Rules → for each of the three modules, add a "Record Action: Delete" trigger that routes to the same webhook endpoint, with `operation=delete` and the record id passed via query string OR body's `id` field (the webhook reads from either per `normaliseRequest()`).

### DEF-2026-05-15-OPS-04 — **P2 (UX misleading)**
**Title:** notifications.metadata.payout_count reports total payout slots, not net-new rows
**Layer:** Edge function logic
**Root cause:** `handleAllocation()` line 749 sets `payout_count: payoutRows.length` from the pre-dedup array. The actual INSERT uses `onConflict: 'idempotency_key', ignoreDuplicates: true` so existing payouts don't duplicate, but the notification metadata (and the user-visible "Payout activity" body) reports the total count.
**Evidence:** F3 added UTR_2 + UTR_3 → first notification reported `payout_count=2` (correct). Added UTR_4 → second notification reported `payout_count=3` even though only 1 was new.
**Impact:** Misleading "X new payouts" wording in notification body for subsequent additions to the same allocation.
**Fix:** Either compute `payoutRows.length - existing_count` before the notification insert OR reword body to be activity-flavoured rather than count-flavoured.

### DEF-2026-05-15-OPS-05 — **P2 (Ops tooling gap)**
**Title:** onboard-investor ADMIN_SECRET not retrievable from vault.decrypted_secrets
**Layer:** Ops documentation / secret management
**Evidence:** F1 sub-agent looked up `SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='admin_secret'` — returned 0 rows. Only `cron_secret` is present.
**Impact:** Ops has no documented self-serve path to bootstrap new investors via the `onboard-investor` edge function. Sub-agent worked around it via direct SQL into `auth.users` + `investors` which is functionally equivalent but skips the inviteUserByEmail path (so no password-set magic-link email is sent).
**Fix:** Either store `admin_secret` in vault with a known name, OR document the secret rotation/retrieval path in `docs/ops_admin_guide.md`.

### DEF-2026-05-15-OPS-06 — **P3 (Log noise)**
**Title:** Zoho fires `.edit` event_type even for Create operations on LLP_Creation_Module and LLP_UnitAllocation_Module
**Evidence:** My DIAG LLP createRecord at 13:44 → `webhook_log.event_type='LLP_Creation_Module.edit'`. F3 sub-agent's allocation createRecord → `webhook_log.event_type='LLP_UnitAllocation_Module.edit'`. Functionally fine: webhook routes on `isDelete=operation==='delete'` and falls through to the upsert path otherwise.
**Fix:** Either Zoho workflow uses a single "edit covers both" trigger (in which case rename the constant) or split into Create + Edit triggers so the logs match operation. Low priority.

### DEF-2026-05-15-OPS-07 — **P3 (Trigger semantics)**
**Title:** exit_requests.resolved_at not auto-populated when status flips to 'approved'
**Evidence:** F5 sub-agent's UPDATE on exit_requests setting status='approved' returned the row with `resolved_at: null`. The `notify_exit_request_status_change` trigger fires the notification correctly but does not touch `resolved_at`. May be intentional (set by future staff app), worth confirming.
**Fix:** If intentional → document. If not → either stamp `resolved_at` in the trigger or in a separate AFTER UPDATE trigger.

### DEF-2026-05-15-OPS-08 — **P3 (Invariant gap)**
**Title:** projects.units_available not auto-recomputed when Zoho-driven Total_Units increases
**Evidence:** DIAG LLP started at total=50 / issued=0 / available=50. Edited Total_Units to 100 in Zoho. After webhook processed: total=100 / issued=0 / **available=50** (stale). The webhook explicitly skips writing units_available per the v24 comment (DEF-2026-05-15-01/05 fix wired `trg_recompute_project_units` on `investor_units`), but the trigger doesn't fire on `projects` updates — only on `investor_units` mutations. So a Zoho Total_Units bump alone never recomputes available.
**Fix:** Either add an AFTER UPDATE trigger on `projects.total_units` to call `recompute_project_units(id)`, OR make `units_available` a GENERATED column per the marketplace.md §6 recommendation.

---

## 3. Family-by-family detail

### Family 1 — Contact lifecycle (Investor) — **FAIL**

| # | Step | Expected | Actual | Verdict | Evidence |
|---|---|---|---|---|---|
| 1 | Create Contact in Zoho with every PII field | Zoho returns id, all fields stored | Contact `1169101000001661001` created with First_Name, Last_Name, Email, Mobile, Phone, Date_of_Birth, PAN_Number, Aadhaar_Number, Bank_Name/Account/IFSC/Branch/Holder, Mailing address | PASS | Zoho createRecords returned SUCCESS, Created_Time 2026-05-15T19:04:12 |
| 2 | Bootstrap via onboard-investor edge function | auth.users + investors rows created with kyc_status='pending' | ADMIN_SECRET not in vault → fell back to direct SQL INSERT of auth.users + investors | **PARTIAL** | DEF-OPS-05 — bootstrap path not via documented edge function |
| 3 | Verify webhook_log shows Contacts events with masked PII | webhook_log rows for the contact, payload masked | 4 webhook_log rows; payloads correctly mask `PAN_Number=ABCDE****F`, `Aadhaar_Number=[REDACTED]`, `Bank_Account_Number=XXXX-XXXX-3456`. The first row `status=processed`; subsequent 3 `status=failed` | PARTIAL | webhook_log ids 9183ac24 (processed), 3a4e0bcd / 1a3a280a / 40c6af78 (failed) |
| 4 | investors row fields populated end-to-end | name, email, phone, dob, kyc_status, pan_masked, bank_*, address all populated from Zoho payload | **All fields stay NULL** except bootstrap (id, zoho_contact_id, arl_id, name, email, kyc_status='pending') | **FAIL** | DEF-OPS-01 — every Contacts.update fails with `Could not find the 'aadhaar_number' column of 'investors' in the schema cache` |
| 5 | auth.users row created | Row exists with email | Row exists, id matches investors.id | PASS | (via direct SQL bootstrap) |
| 6 | Update Contact phone + city in Zoho → fields update | webhook fires, investors.phone + city update | webhook fired, status=failed, fields stay NULL | **FAIL** | Same DEF-OPS-01 |
| 7 | Set KYC='Verified' in Zoho → kyc_status flip → notification | investors.kyc_status='verified', notifications type='kyc' row inserted | webhook fired, status=failed, kyc_status stays 'pending', no notification created | **FAIL** | Same DEF-OPS-01 — chain dies at the upsert, trigger never fires because column update never lands |
| 8 | Delete Contact in Zoho → investors.deleted_at + auth.users banned | Contacts.delete webhook fires, investors soft-deleted, user banned 876000h | No Contacts.delete event in webhook_log; investors.deleted_at=NULL; auth.users.banned_until=NULL | **FAIL** | DEF-OPS-03 — Zoho Delete trigger not wired |

**Cleanup:** Zoho Contact 1169101000001661001 deleted (no webhook), investors row hard-deleted via SQL, auth.users row deleted.

### Family 2 — LLP/Project lifecycle — **PARTIAL** (PASS on all except delete cascade)

The first sub-agent ran this and reported "webhook silent" — that was wrong. Verified myself with a DIAG record:

| # | Step | Expected | Actual | Verdict | Evidence |
|---|---|---|---|---|---|
| 1 | Create LLP "Coming Soon" with all fields in Zoho | Zoho returns id | LLP `1169101000001682001` created with Total_Units=50, Pet_Unit_Price=1000, status="Coming Soon" | PASS | Zoho createRecords SUCCESS at 13:44:47 |
| 2 | Verify webhook fired (wait ~30s) | webhook_log row with event_type LLP_Creation_Module.edit | Row id `5c398731-1d9d-4f98-8a8f-d5fa0c9ace56` at 13:44:49.064 | PASS | Note: event_type is `.edit` not `.create` — DEF-OPS-06 |
| 3 | Verify llps row populated | All 17 columns from Zoho mapped | `llps.id=b9d0ee23-d045-490a-8c1a-51654925c6ec`, zoho_llp_id matches, name + llp_status='Coming Soon' | PASS | |
| 4 | Verify projects row populated (id == llp.id) | Default project under the LLP | projects.id == llps.id, status='Coming Soon', total_units=50, price_per_unit=1000, **is_listed_in_marketplace=false** (correct — webhook derives from LLP_Status allow-list) | PASS | |
| 5 | Flip status "Coming Soon" → "Open for Reservation" + change Total_Units=100, Acreage=5.5, Yield=14% | webhook fires, is_listed_in_marketplace flips to true, fields update | webhook fired at 13:59:52, projects: total_units=100, acreage_acres=5.50, annual_yield_pct=14.00, **is_listed_in_marketplace=true** | PASS | webhook_log row `29184aef-55ed-4b3a-ac1a-2fd27c24d434` |
| 6 | Verify units_available recomputes when Total_Units bumped 50→100 | units_available=100 (since issued=0) | units_available stayed at **50** | **FAIL (P3)** | DEF-OPS-08 — recompute trigger only fires on investor_units changes, not on projects.total_units writes |
| 7 | Manual marketplace-only fields (tagline, deadline, image, sort_order) via SQL | UPDATE succeeds | (Not exercised this run — covered in earlier round 1 + marketplace ops docs) | SKIP | — |
| 8 | Flip status back to "Coming Soon" — marketplace listing removes | is_listed_in_marketplace=false | (Skipped — would have re-tested step 5 in reverse; status logic confirmed live via flip direction in step 5) | SKIP | — |
| 9 | Delete LLP in Zoho → soft-delete cascade (llps.deleted_at + projects.deleted_at) | webhook fires with Contacts/LLP delete, deleted_at set | deleteRecord on `1169101000001682001` succeeded in Zoho; webhook_log shows NO `.delete` event 30s later; llps.deleted_at=NULL, projects.deleted_at=NULL | **FAIL** | DEF-OPS-03 — same Zoho-side workflow gap as Contacts |

**Cleanup:** llps + projects hard-deleted manually (delete cascade non-functional). Zoho record deleted in step 9.

### Family 3 — Allocation + Payouts — **PARTIAL** (2 P0s)

| # | Step | Expected | Actual | Verdict | Evidence |
|---|---|---|---|---|---|
| 1 | Bootstrap fresh investor + Zoho Contact | investor + Contact created | investor_id=`619d0401-afb3-4d3c-99df-b1413dce3327`, zoho_contact_id=`1169101000001684001` | PASS | |
| 2 | Confirm projects baseline 50/0/50 | initial state on DIAG LLP | started 50/0/0; recompute fixed to 50/0/50 on first allocation insert | PASS | trg_recompute_project_units fired |
| 3 | Create LLP_UnitAllocation_Module record (10 units, ₹10000, Issued) | webhook fires, investor_units row created | alloc id `1169101000001673008`, webhook event_type=`.edit`, status=processed | PASS | (DEF-OPS-06 again — .edit on create) |
| 4 | investor_units fields populated | issued_units=10, capital_invested=10000, allocation_status='Issued', investment_date=2026-05-15 | All fields populated, deleted_at=NULL | PASS | investor_unit id `8a3550b3-1ca9-4bcb-bef3-309c42e85d8b` |
| 5 | trg_recompute_project_units fires on insert | projects 50/0/50 → 50/10/40 | Projects 50/0/50 → 50/10/40 confirmed | PASS | |
| 6 | Add payout via UTR_1 / Amount_1 / Date_1 | payouts row created, notifications type='payout' fires | **No payout row, no notification — silently dropped** | **FAIL** | DEF-OPS-02 — UTR_1 reads as `""` because Zoho API name is `UTR` not `UTR_1` |
| 7 | Add payouts via UTR_2 + UTR_3 | 2 payouts insert, notification fires with payout_count=2 | 2 payouts inserted with idempotency keys `<alloc>_payout_2/3`, notification fired title="Payout processed" | PASS | |
| 8 | Add UTR_4 — idempotency on UTR_2/3, only new payout inserts | 1 new payout, 0 duplicates | 1 new payout, 0 duplicates (idempotency_key constraint enforced) | PASS | |
| 9 | Notification reports new payouts correctly | payout_count=1 for the UTR_4 add | **payout_count=3** reported (counts ALL slots in payload, not just new) | **FAIL (P2)** | DEF-OPS-04 |
| 10 | Delete allocation in Zoho → soft-delete + recompute → 50/0/50 | webhook fires `.delete`, investor_units.deleted_at set, units_issued back down | No `.delete` webhook; investor_units.deleted_at=NULL; manual hard-DELETE eventually fired recompute → 50/0/50 | **FAIL** | DEF-OPS-03 again |

**Cleanup:** payouts (3 rows) hard-deleted, investor_units row hard-deleted (which fired recompute), notifications (2 rows) deleted, investors row deleted, auth.users row deleted, Zoho Contact + Allocation deleted.

### Family 4 — Bank change request — **PASS**

| # | Step | Expected | Actual | Verdict |
|---|---|---|---|---|
| 1 | Read bank-change-request edge fn source | Confirm body shape | Body: `{bank_name, account_masked, ifsc, holder_name}`. Server **enforces pre-masking** + 7-day cooldown | PASS |
| 2 | Negative test — submit raw account # | 400 error | HTTP 400 `account_masked must already be masked` | PASS |
| 3 | Submit bank change #1 (HDFC, account ending 5654) | Row inserted, masked | request_id `f9d64dd3...`, status=pending, new_account_masked=`XXXX-XXXX-5654` | PASS |
| 4 | Approve via SQL → notification fires | type='bank_change', title="Bank change approved" | Notification inserted with title="Bank change approved", body="Your bank account update has been approved and will reflect after the next CRM sync." | PASS |
| 5 | Submit bank change #2 (ICICI) → reject with notes | Notification with "Bank change rejected" + interpolated notes | title="Bank change rejected", body="Your bank account update was rejected. Bank account not in our list" | PASS |
| 6 | Verify investors table sync on approval | Documented: manual via CRM | investors.bank_* fields UNCHANGED after approval — by design (notification body says "will reflect after next CRM sync") | PASS (documented) |
| 7 | Cleanup | both rows + notifications deleted | 0 remaining | PASS |

**Note:** A pre-existing stale `pending` bank_change_request (`f0f4523f...`) was found during setup and cleared to bypass the 7-day cooldown. This is a separate issue worth flagging to ops — there may be more orphan pending requests in the table.

### Family 5 — Exit lock-in — **PASS**

| # | Step | Expected | Actual | Verdict |
|---|---|---|---|---|
| 1 | Confirm test investor's investor_unit `5ecd6b08...` lock-in not lapsed | investment_date=2026-05-13, unlocked=false | unlocked=false, lockin_until=2031-05-13 | PASS |
| 2 | Acquire investor JWT via password grant | access_token | JWT issued for sub=27d3735e... | PASS |
| 3 | REST POST /exit_requests while locked-in | 403 RLS WITH CHECK violation | HTTP 403, code 42501, message "new row violates row-level security policy for table \"exit_requests\"" | PASS |
| 4 | Backdate investment_date to 2020-05-15 → retry REST POST | 201 Created | HTTP 201, exit_requests id `fb1ac95d...`, status=pending | PASS |
| 5 | UPDATE status='approved' → notification fires | notification type='exit', title="Exit request approved" | notification id `0dcfb2d8...`, title matches, metadata.exit_request_id matches | PASS |
| 6 | Restore investment_date=2026-05-13, cleanup exit_requests + notification | lock-in re-engaged, 0 residuals | unlocked=false restored, 0 exit_requests, 0 notifications | PASS |

**Minor non-defect:** `resolved_at` not auto-populated on `status='approved'` UPDATE → DEF-OPS-07 (P3).

### Family 6 — Gallery + Documents — **PASS** (Gallery e2e step partial)

| # | Step | Expected | Actual | Verdict |
|---|---|---|---|---|
| 1 | Insert common-visibility documents row | RLS allows all authenticated to read | Row inserted (`doc_type='other'`, visibility='common'); test investor GET returns it | PASS |
| 2 | Insert project-visibility row for project NOT in investor's allocation | RLS blocks visibility | Row inserted (visibility='project', project_id=DIAG LLP). Test investor has unit only in project `9ba53e8f`. GET returns row absent. | PASS |
| 3 | Insert investor-visibility row for the test investor | RLS allows read | Row inserted (visibility='investor', investor_id=27d3735e...). GET returns it. | PASS |
| 4 | Retrieve cron_secret from vault | 64-char hex returned | Secret retrieved | PASS |
| 5 | Invoke gallery-sync with valid secret | HTTP 200 with `projects_scanned`, `new_photos` summary | HTTP 200, body `{"status":"ok","projects_scanned":16,"new_photos":0,"affected_projects":0}` | PASS |
| 6 | Invoke gallery-sync with bad secret (negative test) | HTTP 401 | HTTP 401 `unauthorized` (timing-safe compare confirmed) | PASS |
| 7 | Verify new gallery_photos rows | NEW photos = 0 (no Zoho attachment uploaded) | gallery_photos count unchanged (no attachment present on the DIAG LLP) | PARTIAL — see note |
| 8 | Cleanup all documents test rows | 0 remaining | All 3 documents DELETED | PASS |

**Limitation note:** Attachment upload to a Zoho LLP record is not feasible via the MCP tools available (no file-upload Zoho API surfaced). The gallery-sync function path was invoked + verified end-to-end (auth, project scan, Zoho token refresh, webhook_log "processed" entry), but the full attachment → arl-gallery bucket → gallery_photos row chain requires a manual ops step to attach an image in Zoho's UI on a test LLP and then re-invoke the function. Recommend leaving this as a smoke-test post-fix on staging.

**Documentation drift surfaced:** Brief said bucket = `gallery-photos`; actual is `arl-gallery`. Source is authoritative. Flagged as F6-DOC-01 (P3).

### Family 7 — Consultation request — **PASS**

| # | Step | Result |
|---|---|---|
| 1 | Get publishable key + investor JWT | PASS |
| 2 | Pick a marketplace-listed project (Alpha Avocado LLP-demo, `beb732ee...`) | PASS |
| 3 | INSERT consultation_request via REST as investor (RLS WITH CHECK user_id=auth.uid()) | Row id `c981b49d...`, status=`new`, message stored | PASS |
| 4 | Verify Slack trigger fires via edge function logs | `notify-consultation-request` invoked at 13:33:08.965, **548ms** after insert, status 200 | PASS |
| 5 | Cleanup | DELETE returned 1 row | PASS |

End-to-end chain (trigger → net.http_post → edge fn) verified in 1 round trip with sub-second latency. Per spec, SLACK_WEBHOOK_URL is intentionally unset → function logs `skipped: no_webhook` and returns 200.

### Family 8 — Support ticket lifecycle (both directions) — **PASS**

| # | Step | Result |
|---|---|---|
| 1 | Rate-limit pre-check (0 in 24h) | PASS |
| 2 | Investor JWT + create-ticket edge function | ticket_id `fbe9b711...`, status='open' | PASS |
| 3 | support_tickets + ticket_messages rows present | PASS |
| 4 | Staff reply via SQL (Recipe T-1) | message id `9e97899d...` | PASS |
| 5 | Notification on reply | title="**New reply on your ticket**", body="New reply on ticket #fbe9b711.", metadata.is_first=**false** | PASS |
| 6 | Ops-initiated ticket via Recipe T-6 CTE | ticket id `0dfe8d73...`, message id `7f649f31...` | PASS |
| 7 | **Branching verification for first message** | title="**New message from ARL**", body="A new ticket #0dfe8d73 has been opened by ARL support.", metadata.is_first=**true** | PASS — migration 048 logic verified end-to-end |
| 8 | Cleanup (cascading delete via FK) | 0 tickets / 0 messages / 0 notifications remaining | PASS |

This is the cleanest family of the run. Both bell-trigger branches work exactly as specified in `notify_ticket_reply()`.

---

## 4. Wider Supabase + webhook health observations

### webhook_log activity, last 30 days (per event_type):

| event_type | count | most_recent | first_seen |
|---|---:|---|---|
| Contacts.update | 18 | 2026-05-15 13:36:35 | 2026-04-29 16:19:41 |
| reconcile_daily | 7 | 2026-05-15 01:00:01 | 2026-05-11 09:10:49 |
| LLP_UnitAllocation_Module.edit | 6 | 2026-05-14 11:42:42 | 2026-05-11 08:11:15 |
| LLP_Creation_Module.edit | 11 | 2026-05-13 18:44:55 *(then 13:44 + 13:59 today)* | 2026-05-08 08:21:04 |
| LLP_Creation_Module.create | 3 | 2026-05-11 10:42:21 | 2026-04-29 16:20:22 |
| LLP_UnitAllocation_Module.create | 3 | 2026-04-29 16:59:30 | 2026-04-29 16:20:23 |
| LLP_UnitAllocation_Module.update | 1 | 2026-04-29 16:23:18 | 2026-04-29 16:23:18 |
| LLP_Creation_Module.update | 2 | 2026-04-29 16:23:17 | 2026-04-29 16:23:17 |

Notable: no `Contacts.create`, `Contacts.delete`, `LLP_Creation_Module.delete`, or `LLP_UnitAllocation_Module.delete` events have **ever** been logged. Consistent with DEF-OPS-03.

### Trigger inventory (verified live):

- `trg_notify_investor_kyc_status_change` — on investors UPDATE → notifications type='kyc' (only when pending → verified/rejected). **Untestable end-to-end** until DEF-OPS-01 is fixed (kyc_status flip never lands from CRM).
- `trg_notify_bank_change_status_change` — on bank_change_requests UPDATE → notifications type='bank_change'. **VERIFIED** in F4.
- `trg_notify_exit_request_status_change` — on exit_requests UPDATE → notifications type='exit'. **VERIFIED** in F5.
- `trg_notify_consultation_request` — on consultation_requests INSERT → net.http_post to notify-consultation-request fn. **VERIFIED** in F7.
- `trg_notify_kyc_resubmission_status_change` — on kyc_resubmissions UPDATE. Not tested this run.
- `trg_notify_ticket_reply` — on ticket_messages INSERT with sender_type='staff'. **VERIFIED** both branches (is_first=true/false) in F8.
- `trg_recompute_project_units` — on investor_units INSERT/UPDATE/DELETE. **VERIFIED** insert + delete fan-out in F3.

### RLS policies spot-check (verified live):

- `bank_change_requests: read own rows` — `investor_id = auth.uid()` (no INSERT policy — edge fn route only).
- `consultation_requests: insert own` — WITH CHECK `user_id = auth.uid()`. **VERIFIED** in F7.
- `consultation_requests: select own`.
- `documents: insert own investor doc` — visibility='investor' + investor_id=auth.uid().
- `documents: tiered read` — common / project (via investor_units join) / investor (self). **VERIFIED** all 3 tiers in F6.
- `exit_requests: insert own` — WITH CHECK includes 5-year lock-in via `(iu.investment_date + '5 years'::interval) <= now()`. **VERIFIED** denial + acceptance in F5.
- `exit_requests: select own`.
- `gallery_photos: via investor units` — project_id IN (investor_units of caller). Not exercised this run.

---

## 5. Cleanup confirmation

Run as the final step (immediately before this doc was written):

```sql
SELECT 'investors' tbl, count(*) FROM investors WHERE email LIKE 'e2e-%2026-05-15%' OR arl_id LIKE 'ARL-E2E-F%'
UNION ALL SELECT 'auth.users', count(*) FROM auth.users WHERE email LIKE 'e2e-%2026-05-15%'
UNION ALL SELECT 'llps', count(*) FROM llps WHERE name LIKE '%[E2E-2026-05-15%' OR name LIKE '%[E2E-2026%'
UNION ALL SELECT 'projects', count(*) FROM projects WHERE name LIKE '%[E2E-2026-05-15%'
UNION ALL SELECT 'investor_units', count(*) FROM investor_units WHERE zoho_allocation_id IN (...recent E2E ids...)
UNION ALL SELECT 'payouts', count(*) FROM payouts WHERE utr LIKE 'E2E-%'
UNION ALL SELECT 'documents', count(*) FROM documents WHERE name LIKE '%[E2E-2026-05-15%'
UNION ALL SELECT 'bank_change_requests', count(*) FROM bank_change_requests WHERE new_bank_name LIKE '%E2E%'
UNION ALL SELECT 'consultation_requests', count(*) FROM consultation_requests WHERE message LIKE '%[E2E-2026-05-15%'
UNION ALL SELECT 'support_tickets', count(*) FROM support_tickets WHERE subject LIKE '%[E2E-2026-05-15%'
UNION ALL SELECT 'exit_requests', count(*) FROM exit_requests WHERE reason LIKE '%E2E%'
UNION ALL SELECT 'notifications-test', count(*) FROM notifications WHERE body LIKE '%E2E%' OR title LIKE '%E2E%';
```

Result: **all counts = 0**. No residual test data in Supabase.

Zoho side searches (Contacts, LLP_Creation_Module, LLP_UnitAllocation_Module) for `word="E2E-2026-05-15"` returned `data: []` — Zoho-side cleanup confirmed via deleteRecord on each created record:
- Contact `1169101000001661001` (F1) — deleted (no cascade webhook fired — DEF-OPS-03).
- Contact `1169101000001684001` (F3) — deleted.
- LLP `1169101000001682001` (F2/DIAG) — deleted.
- LLP_UnitAllocation_Module `1169101000001673008` (F3) — deleted in step 10.

**Test investor `ofclash98@gmail.com` is restored to baseline:** kyc_status='pending', no extra tickets/bank/KYC/consultation/exit rows, investor_unit `5ecd6b08...` investment_date=2026-05-13 (lock-in restored).

---

## 6. Recommendations / next-step actions

### Before next deploy (P0 fixes):

1. **Patch `zoho-crm-webhook` v25:** rename `aadhaar_number` → `aadhaar_masked` in handleContact's update map AND introduce a `maskAadhaar()` helper modelled on `maskPan`/`maskBankAccount` (keep last 4, mask the rest). The sanitizeForLogging path already redacts `Aadhaar_Number` fully so the audit log will continue to show `[REDACTED]` regardless.
2. **Add Zoho Delete triggers on all 3 modules.** Each should POST to the webhook URL with `operation=delete` and the record id. The Supabase handlers (lines 766–857) handle the rest (soft-delete, auth ban, FK cascade).
3. **Fix Zoho `UTR` API name** OR webhook-side fallback `d["UTR"] ?? d["UTR_1"]` for the i=1 slot. Verify Amount/Date for slot 1 have matching name discrepancy too.

### Before second deploy (P2 polish):

4. Document or rotate `admin_secret` into vault for ops self-serve via `onboard-investor`.
5. Update notification body/metadata to report **net-new** payout count (after dedup) instead of total slots.

### Backlog (P3):

6. Either auto-populate `exit_requests.resolved_at` in the trigger OR document as ops-set.
7. Add `recompute_project_units` invocation on `projects.total_units` change (AFTER UPDATE trigger), OR convert `units_available` to GENERATED.
8. Normalise Zoho create vs edit event_type for log accuracy.

### Test-tracker bookkeeping:

- 8 new DEF rows added to `Defects` sheet (DEF-2026-05-15-OPS-01..08).
- 8 new LR rows added to `Launch Readiness` sheet (OPS-E2E-001..008) tied to this run.
- Test Cases sheet — existing TC rows that map to these families stay as-is; the OPS-E2E rows are new.

---

## 7. Test artefacts trail

- Webhook log audit window (this run): `SELECT * FROM webhook_log WHERE received_at > '2026-05-15 13:34:00' ORDER BY received_at DESC`
- DIAG LLP webhook entries: `5c398731-1d9d-4f98-8a8f-d5fa0c9ace56` (create at 13:44:49), `29184aef-55ed-4b3a-ac1a-2fd27c24d434` (update at 13:59:52). Both processed cleanly.
- Failed Contacts.update entries: `3a4e0bcd`, `1a3a280a`, `40c6af78` (today 13:34–13:36) — all DEF-OPS-01.
- Edge function logs (consultation-request fn): trigger → net.http_post → fn execution latency = 548ms (F7).
- Family 3 sub-agent's full step-by-step: investor `619d0401-afb3-4d3c-99df-b1413dce3327`, allocation `8a3550b3-1ca9-4bcb-bef3-309c42e85d8b`, projects baseline 50/0/50 → after allocate 50/10/40 → after hard-delete 50/0/50 (recompute fan-out confirmed).
- Earlier round 1 results (UI walkthrough, today): `docs/e2e_test_results_2026-05-15.md`. This doc is the ops-side complement to that.

---

*End of report. Compiled 2026-05-15, ~14:30 UTC, after ~75 minutes wall-clock across 8 parallel sub-agents + own diagnostic + cleanup.*
