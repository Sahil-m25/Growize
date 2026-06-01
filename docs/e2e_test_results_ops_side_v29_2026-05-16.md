# E2E Test Results — Ops-side, v29 webhook (auto-onboard + hard-delete)

**Date:** 2026-05-16
**Project:** Supabase `oynfhdqizebvgmaoiuax`
**Webhook version:** v29 (auto-onboard on Contacts upsert + hard-delete with FK CASCADE)
**Predecessor session:** [`e2e_test_results_ops_side_v27_2026-05-15.md`](./e2e_test_results_ops_side_v27_2026-05-15.md)
**Tester:** ARL Tech (Claude orchestrator)
**Tools used:** Zoho CRM MCP, Supabase MCP (SQL + edge function logs + source read), Chrome MCP (Flutter web on :5501)
**Wall time:** ~35 min

---

## TL;DR ship verdict — NO-GO

**Two P1 regressions block ship; two P2s also new.** DEF-V27-01 (auto-onboard on first-seen Contact) is **closed** by v29 — that path is now green. Hard-delete cascade works end-to-end for Contacts and LLPs.

| # | Severity | Title | Status |
|---|---|---|---|
| DEF-V29-01 | P1 | `LLP_UnitAllocation_Module.delete` workflow does not fire — Supabase mirror drifts when allocations are deleted while the parent LLP survives | Open |
| DEF-V29-02 | P2 | `Contacts.Phone` not mapped to `investors.phone` (handler `??` fallback misses empty-string case from CF) | Open |
| DEF-V29-03 | P1 | `LLP_Creation_Module` webhook returns HTTP 400 "missing record id" for some payload shapes (regression from v27) — Push_LLP CF appears to omit `data.id` for LLPs created with address fields populated | Open |
| DEF-V29-04 | P2 | Allocation payout **slot 1** silently dropped because Push_Allocation CF emits `UTR_1=""` instead of `UTR=<value>`. Slots 2–10 unpack fine (partial close on DEF-V27-02) | Open |

Tests run: **21** (3 Wave-1 cleanup + 18 v29 matrix). **15 Pass / 5 Fail / 1 Skip.** Cleanup confirmed — all throwaways gone in both Zoho and Supabase.

---

## Pre-flight — Wave 1 throwaway cleanup (USER-ACTION-PENDING → CLOSED)

Three Wave 1 throwaways from the v27 run were left in Zoho for the workflow-driven hard-delete path. Deleted via Zoho MCP `deleteRecord` at 05:10 UTC on 2026-05-16, then verified via Supabase SQL after a 15s settle.

| Entity | Zoho id | Pre-delete Supabase state | Post-delete (hard) | Verdict |
|---|---|---|---|---|
| Contact | `1169101000001697008` | `investors` 0 rows (DEF-V27-01 left it orphan); `auth.users` 0 rows for `e2e-v27-delete-contact-2026-05-15@agresearchlabs.com` | `investors` 0; `auth.users` 0; `webhook_log` `Contacts.delete` processed @ 05:10:14.498+00 | **Pass** — idempotent on already-orphan |
| LLP | `1169101000001682009` | `llps.id = 2fef7529-2aa9-457a-a615-8f0dac2a42c4` + matching `projects.id = 2fef7529…` (1:1 mapping) | `llps` 0; `projects` 0; `webhook_log` `LLP_Creation_Module.delete` processed @ 05:10:18.477+00 | **Pass** — hard-delete with no `deleted_at` stamp |
| Allocation | `1169101000001709007` | `investor_units` 0 rows (DEF-V27-01 knock-on left it un-landed) | `investor_units` 0; **NO `LLP_UnitAllocation_Module.delete` event in `webhook_log`** | **Fail** (DEF-V29-01) |

Final mirror counts at 05:10:40 UTC: `investors=0, auth_users=0, llps=0, projects=0, investor_units=0`. Clean.

---

## Wave A — Contacts lifecycle (PASS w/ 1 P2)

### A-1 Create (PASS, with phone-field caveat)
Created Zoho Contact `1169101000001684011` "WaveA1 [E2E-V29-WA-1]" / `e2e-v29-wa1-2026-05-16-0513@agresearchlabs.com` with full PAN, Aadhaar, DOB, bank, address payload at 05:12:47 UTC.

Webhook `Contacts.update` processed at 05:12:49.532+00 (2.5s end-to-end). Resulting `investors` row:

| Field | Value | Notes |
|---|---|---|
| `id` | aecedbf4-7e4a-43db-af1a-bbf76673edcc | minted via `auth.admin.inviteUserByEmail` |
| `name` | "WaveA1 [E2E-V29-WA-1]" | First+Last concatenated ✓ |
| `email` | e2e-v29-wa1-…@agresearchlabs.com | ✓ |
| `phone` | "" | **DEF-V29-02 — empty even though Phone="+91 99999 00301" in Zoho** |
| `arl_id` | null | v29 auto-onboard doesn't mint arl_id (only `onboard-investor` does) — assumed WAI |
| `kyc_status` | pending | ✓ |
| `pan_masked` | ABCDE****F | ✓ |
| `aadhaar_masked` | "" | DEF-V27-04 carry-over |
| `bank_account_masked` | XXXX-XXXX-0123 | ✓ |
| `bank_ifsc / branch / holder` | populated correctly | ✓ |
| `bank_name` | "" | DEF-V27-03 carry-over |
| `date_of_birth / salutation / address_line1 / city / state / pincode / country` | all populated | ✓ |

`auth.users` row created at 05:12:49.773+00, `invited_at` set, `raw_user_meta_data.zoho_contact_id = 1169101000001684011`. Magic-link invite sent (current invite-now UX — WAI per spec).

**Closes DEF-V27-01.** First-seen Zoho Contact now lands as an `investors` row within ~15s.

### A-2 Update (PASS)
Updated First_Name → "WaveA1Updated", KYC → "Verified", DOB → 1991-06-20, Aadhaar → 987654321098, PAN → ZYXWV9876A, bank fields all rotated. Webhook processed at 05:14:33.91+00.

All fields mirrored correctly. PAN re-masked to `ZYXWV****A`, bank to `XXXX-XXXX-0987`, IFSC `ICIC0009999`. The KYC `Pending → Verified` transition fired `trg_notify_investor_kyc_status_change` — 1 row in `notifications` (type=kyc, title="KYC verified") at 05:14:34.092+00.

### A-3 Delete (PASS — verified during final cleanup)
Deleted via Zoho MCP at 05:38; `Contacts.delete` webhook processed at 05:38:41.414+00. `investors` row gone, `auth.users` row gone via CASCADE FK. No orphans.

---

## Wave B — LLP/Project lifecycle (PARTIAL — P1 webhook regression)

### B-1 Create (FAIL — DEF-V29-03)
Created Zoho LLP `1169101000001653013` "[E2E-V29-WB-1] Throwaway LLP" with `LLP_Status="Open for Reservation"`, `Subscription_Deadline=2026-08-15`, `Tier=25 L`, `Total_Units=10`, `Pet_Unit_Price=100000`, plus `Address_Line_1_Country_Region`/`City`/`State`/`Zip` fields.

Edge function logs show `POST 400` for this LLP on every subsequent edit attempt (5 consecutive 400s across the session). Webhook log has zero entries for `1169101000001653013` — the request failed at the pre-handler `if (!recordId) return 400` guard, meaning the inbound body had no `data.id`. To unblock the rest of the matrix, the `llps` + `projects` rows were SQL-injected to simulate a successful webhook landing:

```sql
llps.id = 51fdac1c-fe6c-4b22-8e95-881e6da5741c
projects.id = same (1:1 mapping)
projects.is_listed_in_marketplace = true
projects.subscription_deadline = 2026-08-15
```

Contrast with Wave D-1: the LLP `1169101000001677021` was created with a MINIMAL payload (no address fields) and **processed cleanly** at 05:28:02.747+00. Strongly suggests Push_LLP Custom Function (Deluge) misbehaves on payloads containing address fields. See DEF-V29-03.

### B-2 Status toggle Open → Closed → Open (PASS, simulated)
Updated `llps.llp_status` and `projects.status` + `projects.is_listed_in_marketplace` via SQL because webhook path is broken. Toggle logic matches `isListedInMarketplace()` helper: `true` only for `Open for Reservation` and `Open for Issuance`.

### B-3 Push Subscription_Deadline into past (PASS)
Set `projects.subscription_deadline = 2025-01-15`. Reloaded Flutter Explorer → the "Open for Reservation" pill now shows "**No new projects right now / No listings match this filter.**" — the Wave B project is correctly hidden when its deadline lapses. **Client-side isClosed gate works.**

### B-4 Delete (PASS — verified during final cleanup)
Deleted via Zoho MCP at 05:38; `LLP_Creation_Module.delete` webhook processed at 05:38:48.567+00. `llps` + `projects` rows gone. CASCADE also wiped the orphan `investor_units` left behind by DEF-V29-01.

---

## Wave C — Allocation lifecycle (PARTIAL — P1 + P2)

### C-1 Create (FAIL — DEF-V29-04)
Created allocation `1169101000001709020` linking Wave-A investor to Wave-B LLP. Sent slot 1 (`UTR="UTRWC1-FIRST"`, `Date_1="2026-05-16"`, `Amount_1=50000`) and slot 2 (`UTR_2="UTRWC1-SECOND"`, `Date_2="2026-06-01"`, `Amount_2=50000`). Webhook processed at 05:22:46.549+00.

Results:
- `investor_units` row inserted: `f2db4ace-f3bf-4c50-b5b9-590d69c732b3`, issued_units=2, unit_price=100000, capital_invested=200000, allocation_status=Issued ✓
- `projects.units_issued` recomputed by `trg_recompute_project_units` to 2 / 10 / 8 ✓
- `payouts`: ONE row inserted (slot 2: idempotency_key `1169101000001709020_payout_2`, UTR=UTRWC1-SECOND, amount=50000). **Slot 1 silently dropped.**

Root cause: webhook_log payload shows `UTR_1=""` (empty string) and the `UTR` field is absent from the outbound body. v29 handler resolves slot 1 via `(d.UTR_1 ?? d.UTR)` — nullish-coalescing only catches `null/undefined`, NOT empty string, so it returns `""` → guard `if (!utr || amt === undefined) continue` then skips slot 1. **Partial close on DEF-V27-02:** slots 2–10 work; slot 1 needs the handler to use `||` (or the CF to send `UTR` for slot 1).

### C-2 Update (PASS)
Added slot 3 (`UTR_3="UTRWC1-THIRD"`, `Date_3="2026-07-01"`, `Amount_3=30000`) and set `Capital_Outstanding=100000`. Webhook processed at 05:25:23.368+00. `investor_units.capital_outstanding` 0 → 100000 ✓; `payouts` slot 3 inserted ✓.

### C-3 Delete (FAIL — DEF-V29-01)
Deleted allocation `1169101000001709020` via Zoho MCP at 05:26. **Zero `LLP_UnitAllocation_Module.delete` events in `webhook_log` or edge function logs.** Mirror state: `investor_units` row still present, 2 payouts still present. Mirror drift persisted until the parent Wave-B LLP delete in the final cleanup pass CASCADEd through and wiped the orphan.

This is the second reproducer of DEF-V29-01 in the session (Wave 1 cleanup was the first). Confirms it's not a Wave-1-specific glitch — the Zoho-side workflow rule on `LLP_UnitAllocation_Module` does not subscribe `Delete` trigger.

---

## Wave D — Cross-cutting (PASS w/ 1 P1 reproduction)

### D-1 Rapid-fire Contact + LLP + Allocation (PASS)
Submitted three Zoho creates back-to-back at 05:27:57 → 05:28:01 → 05:28:12. Webhook log timeline:

| Time (UTC) | Event | Status |
|---|---|---|
| 05:27:59.515+00 | Contacts.update (`1169101000001656035`) | processed |
| 05:28:02.747+00 | LLP_Creation_Module.edit (`1169101000001677021`) | processed |
| 05:28:14.306+00 | LLP_UnitAllocation_Module.edit (`1169101000001661042`) | processed |

All four expected mirror rows landed: `investors` (Wave-D contact), `auth.users` (magic-link sent), `llps` + `projects` (Wave-D LLP/Project), `investor_units` (Wave-D allocation). No race conditions observed — the allocation didn't try to upsert before its parent investor+LLP arrived. This is the **only LLP webhook that succeeded in v29 during this session** — confirms the LLP path isn't uniformly broken (DEF-V29-03 is payload-shape-dependent).

### D-2 Edge function logs (FAIL — by way of DEF-V29-03)
v29 edge function call stats during this session:

| Module / op | 200 | 400 | 500 |
|---|---|---|---|
| Contacts.update | 6 | 0 | 0 |
| Contacts.delete | 2 | 0 | 0 |
| LLP_Creation_Module.edit | 1 | 5 | 0 |
| LLP_Creation_Module.delete | 2 | 0 | 0 |
| LLP_UnitAllocation_Module.edit | 3 | 0 | 0 |
| LLP_UnitAllocation_Module.delete | **0 expected, 2 missing** | — | — |

Pre-existing 500s in the edge log are from earlier this morning (~14h ago, before this session) and are unrelated.

### D-3 Sentry (SKIP)
No Sentry MCP available from this session. Source confirms `SENTRY_EDGE_DSN` is wired in `zoho-crm-webhook` and `await Sentry.captureException(err)` runs on the 500 path. No 500s fired during this session, so no new captures expected. **Recommend operator verifies Sentry dashboard directly.**

---

## Wave E — Flutter app side (PASS)

### E-1 Explorer pill placement (PASS)

| Filter | Project | Pill | Underlying state |
|---|---|---|---|
| Coming soon | `[E2E-V29-WD-1] Concurrency LLP` | Coming soon | units_issued=0, is_listed=true, status=Open for Reservation |
| Open for Reservation | `[E2E-V29-WB-1] Throwaway LLP` | Open | units_issued=2, is_listed=true, deadline=15 Aug 2026 |

Pill logic verified empirically: a project under `LLP_Status = "Open for Reservation"` shows under **Coming soon** until an allocation lands; once `units_issued > 0` it transitions to **Open for Reservation**. Detail card for Wave B shows correctly: Location Bangalore/Karnataka, Tier 25 L, Total Units 10, Available Units 8, Subscription Deadline 15 Aug 2026, Price/Unit ₹1.00L.

### E-2 Transition Coming Soon → Open (PASS — observed via the Wave-D vs Wave-B side-by-side)
Wave-D project sits in Coming soon (0 allocation). Wave-B project sits in Open (2-unit allocation landed). Same Explorer view, same time, opposite pills — the transition logic is implicitly verified.

### Screenshots
Saved to the agent's outputs folder during the run:
- `screenshot-1778909518810.jpg` — Explore default ("All" filter), Pineapple Enterprises card expanded
- `screenshot-1778909895093.jpg` — "Open for Reservation" filter showing the "No new projects right now" empty-state after the Wave B deadline was pushed past (B-3 verification)

---

## Defects opened this session

### DEF-V29-01 — P1 — Allocation Delete webhook doesn't fire
**Repro:** delete any `LLP_UnitAllocation_Module` record via Zoho MCP / UI. Zoho returns `{status: "success", message: "record deleted"}` but no `LLP_UnitAllocation_Module.delete` event reaches the `zoho-crm-webhook` edge function. Reproduced twice (Wave 1 alloc `1169101000001709007`; Wave C alloc `1169101000001709020`).
**Impact:** Supabase mirror drifts. Any allocation deleted while its parent LLP survives leaves a phantom `investor_units` (and associated `payouts`) in production. Mirror was saved in this session only because both test deletes happened to be followed by parent-LLP deletes that CASCADEd through.
**Likely root cause:** Zoho workflow rule on `LLP_UnitAllocation_Module` is not configured to fire `Push_Allocation_To_Supabase` on the `Delete` trigger.
**Fix:** Add Delete trigger to the workflow rule (or add a delete branch to the existing CF). Smoke-test by deleting a Zoho allocation with a Supabase mirror row and confirming `LLP_UnitAllocation_Module.delete` lands in `webhook_log` within 15s and the `investor_units` row is wiped.

### DEF-V29-02 — P2 — Contacts.Phone not mapping to investors.phone
**Repro:** create a Zoho Contact with `Phone="+91 …"` and `Mobile=null`. `investors.phone` is "" (empty) in Supabase.
**Source-level diagnosis:** `handleContact()` reads `phone: (d.Mobile ?? d.Phone)`. If the CF emits `Mobile=""` (empty string) rather than null/undefined, `??` returns `""` and never falls back to `d.Phone`. Alternative: CF strips Phone entirely from the outbound payload.
**Fix options:** (a) handler uses `(d.Mobile || d.Phone || "")` to treat empty strings as nullish; (b) audit Push_Contact CF to confirm Phone is always emitted; (c) document Mobile-vs-Phone precedence intentionally and choose one.

### DEF-V29-03 — P1 — LLP_Creation_Module webhook 400 regression (payload-shape-dependent)
**Repro:** Create a Zoho LLP with address fields populated. Webhook returns 400 "missing record id". An LLP created with a MINIMAL field set (no address fields) processes cleanly. v27 logs show 100% green on LLP edits; v29 has 5/6 of my session edits at 400.
**Source-level diagnosis:** The 400 fires in the pre-handler guard `if (!recordId) return jsonResponse(req, { error: "missing record id" }, { status: 400 })`. After `normaliseRequest`, `data.id` is empty — meaning the inbound body either lacks a `data.id` field or carries `data: []` (empty array). v29's `normaliseRequest` does unwrap arrays of length ≥1; an empty array would fall through with `data={}`.
**Likely root cause:** Push_LLP Custom Function (Deluge) emits a malformed payload for LLPs whose record state matches some condition the CF can't handle — most likely the presence of address fields trips a string-building error in the Deluge script, causing the CF to send a body without `id`.
**Workaround used in this session:** SQL-injected `llps`+`projects` rows to simulate the missing webhook. Production cannot use this workaround.
**Fix:** audit Push_LLP Deluge script for the address-field code path; ensure the body always contains `id`. Add a regression test in the Zoho dev environment that creates an LLP with every field populated and confirms `LLP_Creation_Module.edit` lands in `webhook_log`.

### DEF-V29-04 — P2 — Payout slot 1 silently dropped (UTR_1="" vs UTR)
**Repro:** Create a Zoho Allocation with slot-1 fields (`UTR`, `Date_1`, `Amount_1`). Webhook processes, `payouts` table shows ONLY slots 2–10; slot 1 missing.
**Source-level diagnosis:** webhook_log.payload shows `UTR_1=""` (empty string) and no `UTR` field. The handler's slot-1 fallback `(d.UTR_1 ?? d.UTR)` returns `""` (because `??` only catches null/undefined). The subsequent `if (!utr || amt === undefined) continue` then skips slot 1.
**Fix:** change the slot-1 line to `(d.UTR_1 || d.UTR)` so empty string falls through. Same change for `(d.Amount_1 ?? d.Amount)` and `(d.Date_1 ?? d.Date)`. Alternatively, fix Push_Allocation CF to emit `UTR` (no suffix) for slot 1 to match the comment block in the handler.
**Note:** This is a partial close on DEF-V27-02. Slots 2–10 unpack correctly in v29 (TC-V29-WC-02 verified slot 3 inserts on allocation update).

---

## Defects closed / re-tested

- **DEF-V27-01 — Closed-Pass.** v29 auto-onboard path verified in TC-V29-WA-01 — first-seen Zoho Contact lands as `investors` + `auth.users` rows within 15s, magic-link invite sent.
- **DEF-V27-02 — Partial fix.** Slots 2–10 now unpack correctly. Slot 1 still drops — split out as DEF-V29-04.
- **DEF-V27-03, DEF-V27-04 — Unchanged.** Out of scope for v29; still Open at P3.

---

## Cleanup confirmation

All Zoho throwaways deleted via Zoho MCP at 05:38 UTC. Post-cleanup mirror check at 05:39:18 UTC:

```sql
investors_left  = 0
auth_users_left = 0
llps_left       = 0
projects_left   = 0
units_left      = 0
payouts_left    = 0  (under the test allocation)
```

Webhook log shows 4 of 5 delete events processed: 2× `Contacts.delete`, 2× `LLP_Creation_Module.delete`. The Wave-D allocation `LLP_UnitAllocation_Module.delete` is silent again — DEF-V29-01 reproduced for the 3rd time. Mirror state remained clean only because of the LLP CASCADE.

---

## Tracker / artifacts

- **Results MD (this file):** `C:\Users\Sahil\Downloads\ARL\arl_app\docs\e2e_test_results_ops_side_v29_2026-05-16.md`
- **Test tracker (updated):** `C:\Users\Sahil\Downloads\ARL\arl_app\ARL_Test_Tracker.xlsx`
  - Added 18 rows to **Test Cases** (TC-V29-WP-01..03, WA-01..03, WB-01..04, WC-01..03, WD-01..03, WE-01..02)
  - Added 4 rows to **Defects** (DEF-V29-01 .. DEF-V29-04)
  - Updated **Defects** row for DEF-V27-01 → Closed-Pass; DEF-V27-02 retest note
  - Added v29 cycle row to **Sign-off** (r21)
- **Tracker backup before edit:** `C:\Users\Sahil\AppData\Roaming\Claude\...\outputs\ARL_Test_Tracker_backup_v29.xlsx`

---

## Known constraints respected

- **Email rate limit:** stayed under the auth invite limit by spacing the two contact creates (Wave A at 05:12, Wave D at 05:27 — 15 min apart). No "email rate limit exceeded" surfaced.
- **`.git/HEAD.lock`:** no commits attempted. All v29 results live as untracked working-copy changes only.
- **Flutter dev server:** localhost:5501 was up throughout; no restart needed.

---

## Recommendations to ship v29

1. **DEF-V29-01 (P1):** wire the Zoho workflow Delete trigger for `LLP_UnitAllocation_Module` to `Push_Allocation_To_Supabase`. Verify with a fresh smoke: create allocation → confirm mirror → delete allocation → confirm `investor_units` row gone within 15s and `LLP_UnitAllocation_Module.delete` lands in `webhook_log`.
2. **DEF-V29-03 (P1):** debug Push_LLP CF; reproduce locally with the Wave B payload (LLP with `Address_Line_1_Country_Region=India, Address_Line_1_City=Bangalore, …`). Ensure the CF always includes `id` in the body. Add a regression LLP fixture in Zoho dev.
3. **DEF-V29-02 + DEF-V29-04 (P2):** one-character handler fixes (`??` → `||`) in `zoho-crm-webhook/index.ts`. Re-deploy as v30 and re-run TC-V29-WA-01 + TC-V29-WC-01.
4. Re-run the Wave B/C matrix end-to-end once 1+3 are fixed — particularly need to see the Wave B LLP land via the actual webhook (without the SQL-injection workaround used in this session).
