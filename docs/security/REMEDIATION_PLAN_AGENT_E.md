# Agent E — Remediation Plan

**Author:** Agent E (Hermes audit), 2026-06-13
**Scope:** Supabase RLS, Edge Functions, DB migrations, repository IDOR patterns
**Severity tallies (post-verification):** 2 P0, 5 P1, 5 P2, 4 P3 (was 17; E-13 was already mitigated by mig 058/059, re-verified)
**Source findings:** `audit_findings.md` `## Agent E` section (E-1 through E-17)

---

## How to use this plan

The plan is broken into **8 atomic PRs** (PR-A through PR-H). Each PR is independently shippable, has a clear rollback path, and ends with a manual verification step. PR order is **roughly by risk reduction**, not by file:

```
PR-A  P0   bank-change-request: input validation + KYC gate         (E-1, E-10, E-11)
PR-B  P0   bank-change-request: OTP step-up auth                    (E-2)
PR-C  P1   notify-consultation-request: fix broken investor lookup  (E-3)
PR-D  P1   latest-app-version: add channel filter + create table    (E-4, E-5)
PR-E  P1   documents-sync: cross-project/cross-investor uniqueness  (E-6, E-7)
PR-F  P2   split CRON_SECRET per function                            (E-8)
PR-G  P2   sync-stale-alert: de-duplicate alerts                     (E-9)
PR-H  P3   repo + ops cleanups                                       (E-12, E-14, E-15, E-16, E-17)
```

**You can ask Claude Code to execute each PR as its own conversation** — paste the PR header + the relevant finding IDs and it has everything it needs.

---

## Verification update (post-publication)

I found one finding (E-13) that is **already mitigated** in the production migrations I hadn't read when writing the audit:

- **E-13 → RESOLVED.** Migration 058 (`058_consents.sql`) added RLS on `consents`. Migration 059 (`059_privacy_rights.sql`) added RLS on `nominees` and `erasure_requests`. The `.eq('investor_id', uid)` Dart filters are now defense-in-depth, not load-bearing.
- **E-15 → re-grade to P3 documentation-only.** The webhook_log payload currently has `{ scanned, updated }` counts only — no PII. Latent footgun for future contributors. Fix is a comment, not a code change.
- **E-16 → re-grade to P3 documentation-only.** The `sync_status` view is service-role-only in practice. Future contributor footgun if the view is ever exposed to investors. Fix is a comment in the view COMMENT.

**Effective tally:** 2 P0, 5 P1, 4 P2, 4 P3 = **15 actionable findings**, down from the 17 originally filed.

---

## PR-A — bank-change-request: input validation + KYC gate (P0)

**Addresses:** E-1 (P0), E-10 (P2), E-11 (P2)
**Files touched:**
- `supabase/functions/bank-change-request/index.ts`

**Changes:**

1. Add a strict IFSC regex after the existing `isAlreadyMasked` check (around line 122):
   ```ts
   // RBI IFSC: 4 letters + 0 + 6 alphanumeric. Case-insensitive in input,
   // canonicalise to upper.
   const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
   if (!IFSC_RE.test(ifsc.trim().toUpperCase())) {
     return jsonResponse(req, {
       error: "invalid_ifsc",
       message: "IFSC must be 11 chars: 4 letters + 0 + 6 alphanumeric (e.g. HDFC0001234).",
     }, { status: 400 });
   }
   ```
2. Add length caps (return 400):
   - `bank_name` ≤ 80 chars
   - `ifsc` ≤ 11 chars (the regex enforces this, but defence-in-depth)
   - `holder_name` ≤ 100 chars
3. Add KYC gate (look up alongside the existing `investors` SELECT on line 183-187):
   ```ts
   const { data: investor } = await supabase
     .from("investors")
     .select("name, arl_id, kyc_status")  // <-- add kyc_status
     .eq("id", investorId)
     .maybeSingle();

   if (!investor || investor.kyc_status !== "verified") {
     return jsonResponse(req, {
       error: "kyc_required",
       message: "Bank change requires KYC verification.",
     }, { status: 403 });
   }
   ```
4. Also store IFSC uppercase-canonicalised in the insert (line 166 `new_ifsc: ifsc` → `new_ifsc: ifsc.trim().toUpperCase()`).
5. Strip leading/trailing whitespace from all four fields before storing/emails.

**Rollback:** `git revert` the commit. The function will accept the prior (broader) input set again — no data migration needed.

**Manual verify after deploy:**
```bash
# 1. Happy path: verified investor, valid IFSC, valid holder_name
curl -X POST \
  -H "Authorization: Bearer $TEST_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d '{"bank_name":"HDFC","account_masked":"XXXX-XXXX-1234","ifsc":"HDFC0001234","holder_name":"Test User"}' \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/bank-change-request
# expect: 200, request_id

# 2. Bad IFSC
... -d '{"bank_name":"HDFC","account_masked":"XXXX-XXXX-1234","ifsc":"hdfc123","holder_name":"Test User"}'
# expect: 400 invalid_ifsc

# 3. 10MB holder_name (boundary)
... -d "{\"bank_name\":\"HDFC\",\"account_masked\":\"XXXX-XXXX-1234\",\"ifsc\":\"HDFC0001234\",\"holder_name\":\"$(head -c 10000000 /dev/urandom | base64)\"}"
# expect: 400 too long

# 4. Unverified investor — request as the seeded pending-kyc test user
# expect: 403 kyc_required
```

---

## PR-B — bank-change-request: OTP step-up auth (P0)

**Addresses:** E-2 (P1 — upgraded to P0 in this PR because account-takeover pivot)
**Files touched:**
- `supabase/functions/bank-change-request/index.ts` (request path)
- `supabase/functions/request-otp/` (NEW function, ~80 lines)
- `lib/core/repositories/support_repository.dart` (add 2 wrapper methods: `requestBankChangeOtp`, `verifyBankChangeOtpAndSubmit`)
- `lib/features/profile/screens/security_screen.dart` (add "Change bank account" flow that gates on OTP)

**Why a separate PR:** this changes the product flow (2-step instead of 1-step), needs a new Edge Function, and touches the Flutter UI. PR-A's hard input-validation is the fire-alarm; PR-B is the actual lock.

**Changes:**

### 1. New Edge Function: `supabase/functions/request-otp/index.ts`

```ts
// Pseudocode — full file ~80 lines
// - Reads Authorization header, resolves investor via auth.getUser
// - Generates a 6-digit OTP, stores it in a NEW table `bank_change_otps` (see migration below)
// - Sends the OTP via Resend to the investor's email
// - TTL: 10 minutes
// - Rate limit: 3 OTPs per 24h per investor
// - 200 even if email send fails (logs warning, doesn't reveal whether email exists)
```

**New migration:** `supabase/migrations/20260615000000_063_bank_change_otps.sql`
```sql
create table public.bank_change_otps (
  id uuid primary key default gen_random_uuid(),
  investor_id uuid not null references public.investors(id) on delete cascade,
  otp_hash text not null,         -- sha256(otp + pepper), never the raw OTP
  requested_payload jsonb not null,  -- bank_name, account_masked, ifsc, holder_name
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  consumed_at timestamptz
);
create index bank_change_otps_investor_idx
  on public.bank_change_otps (investor_id, created_at desc);
alter table public.bank_change_otps enable row level security;
-- no policy: only service_role touches this table
```

### 2. Modify `bank-change-request` to require `otp` in body
- New body shape: `{ bank_name, account_masked, ifsc, holder_name, otp }`
- Verifies the OTP via `bank_change_otps` (consumes the most recent unexpired one matching sha256(otp + pepper))
- If OTP is invalid/missing: returns 401 `error: "otp_required"`
- On success: deletes the consumed OTP, proceeds with the existing insert (PR-A's input validation still runs first)

### 3. Flutter changes (support_repository.dart + security_screen.dart)
- `requestBankChangeOtp(...)` — calls `request-otp` with the proposed bank change payload, returns `request_id`
- `submitBankChangeWithOtp(requestId, otp)` — calls `bank-change-request` with the `otp` field
- Security screen UI: a 2-step modal: (1) user enters new bank details, taps "Send OTP", (2) shows OTP field, user enters 6-digit code, taps "Confirm"

**Rollback:** `git revert` the new function + the modified `bank-change-request` + drop the new migration. The Flutter wrapper methods can be no-ops (already-shipped users get "OTP not yet enabled" until they update).

**Manual verify after deploy:**
```bash
# 1. Request OTP
curl -X POST -H "Authorization: Bearer $TEST_INVESTOR_JWT" \
  -d '{"bank_name":"HDFC","account_masked":"XXXX-XXXX-1234","ifsc":"HDFC0001234","holder_name":"Test User"}' \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/request-otp
# expect: 200, request_id (and an email sent)
# Grab the OTP from the email (or from the test mailtrap)

# 2. Submit with OTP
curl -X POST -H "Authorization: Bearer $TEST_INVESTOR_JWT" \
  -d '{"bank_name":"HDFC","account_masked":"XXXX-XXXX-1234","ifsc":"HDFC0001234","holder_name":"Test User","otp":"123456"}' \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/bank-change-request
# expect: 200, request_id (the actual bank-change row created)

# 3. Submit without OTP — expect 401
# 4. Replay the same OTP — expect 401 (consumed)
# 5. Wait 10 min and resubmit — expect 401 (expired)
# 6. Request 4 OTPs in an hour — expect 429 on the 4th
```

**Note for the team:** A penny-drop verification (a 1 INR deposit from ARL to the new account, then investor reads the deposit amount) is the strongest option but requires banking integration. OTP is the 80/20 — ship OTP first, add penny-drop in a follow-up quarter.

---

## PR-C — notify-consultation-request: fix broken investor lookup (P1)

**Addresses:** E-3 (P1)
**Files touched:**
- `supabase/functions/notify-consultation-request/index.ts`

**The bug in one line:** line 120 queries `.eq("user_id", consultation.user_id)` against the `investors` table, but the `investors` table has no `user_id` column — its primary key is `id` and `id` IS the auth.users(id). So the query ALWAYS returns null, and every Slack post says "Unknown investor" with empty email + phone.

**The fix (one line):**
```ts
// Line 120, in supabase/functions/notify-consultation-request/index.ts
// OLD:
  .eq("user_id", consultation.user_id)
// NEW:
  .eq("id", consultation.user_id)
```

That's it. One character group changed.

**Also add a fallback:** if the lookup still returns null (orphan row), log a warning and post the request with what we have (project name, message) plus the raw `user_id` so ops can correlate manually. This is a 5-line addition.

**Also clean up:** the function reads `investor.full_name` from the table, but the `investors` table column is `name` (not `full_name` — there's no such column in migration 002). Even after the `.eq` fix, the `.select("full_name, email, phone")` would return null for `full_name`. Fix:
```ts
// Line 119 — also fix the select
  .select("name, email, phone")  // was "full_name, email, phone"
```

And downstream on line 126-128:
```ts
const investorName = (investor?.name as string | undefined) ?? "Unknown investor";
```

**Rollback:** `git revert` (one-line change).

**Manual verify after deploy:**
```bash
# 1. Insert a consultation request directly (use the seeded test investor)
psql -h oynfhdqizebvgmaoiuax -U postgres -d postgres -c "
INSERT INTO consultation_requests (user_id, project_id, units_requested, message)
VALUES ('<TEST_INVESTOR_UUID>', '<TEST_PROJECT_UUID>', 5, 'Smoke test for Slack notify');
"

# 2. Wait 5-10s for the trigger to fire and the function to complete
# 3. Check the Slack channel for a message like:
#    "New consultation request from <Test Investor> on <Test Project>"
#    (previously: "from Unknown investor")
# 4. Verify the email + phone are populated
```

---

## PR-D — latest-app-version: add channel filter + create the table (P1)

**Addresses:** E-4 (P1), E-5 (P1)
**Files touched:**
- `supabase/functions/latest-app-version/index.ts`
- NEW migration: `supabase/migrations/20260616000000_064_app_releases.sql`
- (optional) `lib/core/repositories/app_config_repository.dart` — add `appRelease()` method

**Changes:**

### 1. New migration: `20260616000000_064_app_releases.sql`
```sql
create table public.app_releases (
  id              uuid primary key default gen_random_uuid(),
  channel         text not null check (channel in ('android','ios','web')),
  version_code    int not null,
  version_name    text not null,
  apk_url         text,
  web_url         text,
  release_notes   text,
  is_critical     boolean not null default false,
  published_at    timestamptz not null default now(),
  -- Enforce channel-URL pairing: web rows have a web_url, native rows have an apk_url.
  -- This prevents "I have an APK but no web URL" or vice versa.
  constraint app_releases_url_pairing check (
    (channel = 'web'  and apk_url is null and web_url is not null) or
    (channel in ('android','ios') and apk_url is not null and web_url is null)
  )
);
create unique index app_releases_channel_version_uniq
  on public.app_releases (channel, version_code);

alter table public.app_releases enable row level security;
-- Public read so the anon latest-app-version call can see the row.
create policy "app_releases: public read"
  on public.app_releases for select
  to anon, authenticated using (true);
-- Only service_role can write (no INSERT/UPDATE/DELETE policies).
grant select on public.app_releases to anon, authenticated;

-- Backfill a v1 release for each channel so the function returns something.
insert into public.app_releases (channel, version_code, version_name, apk_url, release_notes)
values
  ('android', 1, '1.0.0', 'https://github.com/agresearchlabs/growize/releases/download/v1.0.0/app-release.apk', 'Initial release.'),
  ('ios',     1, '1.0.0', 'https://apps.apple.com/in/app/growize/id000000000',                            'Initial release.'),
  ('web',     1, '1.0.0', 'https://app.growize.in',                                                       'Initial release.');
```

### 2. Modify `latest-app-version` to accept a channel parameter
```ts
// In supabase/functions/latest-app-version/index.ts around line 64:

// Read the channel from a query-string param (preferred for GET) or a header.
const url = new URL(req.url);
const channel = (url.searchParams.get("channel")
  ?? req.headers.get("x-app-channel")
  ?? "android") as "android" | "ios" | "web";

if (!["android", "ios", "web"].includes(channel)) {
  return jsonResponse(req, { error: "invalid_channel" }, { status: 400 });
}

const { data, error } = await supabase
  .from("app_releases")
  .select("version_code, version_name, apk_url, web_url, release_notes, is_critical")
  .eq("channel", channel)            // <-- add this
  .order("version_code", { ascending: false })
  .limit(1)
  .maybeSingle();
```

### 3. Add Dart client call (so the Flutter app sends its channel)
```dart
// lib/core/repositories/app_config_repository.dart — add:
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

Future<Map<String, dynamic>> appRelease() async {
  final client = ArlSupabase.client;
  if (client == null) return const {};
  final channel = _detectChannel();
  final res = await client.functions.invoke(
    'latest-app-version',
    queryParameters: {'channel': channel},
  );
  return (res.data as Map<String, dynamic>?) ?? const {};
}

String _detectChannel() {
  if (kIsWeb) return 'web';
  return defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';
}
```

**Rollback:** `git revert` the function + Dart call + drop the new table. The function will gracefully return the empty response (no rows match) and the client treats itself as up-to-date — same as today.

**Manual verify after deploy:**
```bash
# 1. No channel — defaults to android
curl 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/latest-app-version'
# expect: {"version_code":1, ..., "apk_url":"https://github.com/...apk", "web_url":null}

# 2. Web channel
curl 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/latest-app-version?channel=web'
# expect: {"version_code":1, ..., "apk_url":null, "web_url":"https://app.growize.in"}

# 3. Invalid channel
curl '.../latest-app-version?channel=foo'
# expect: 400 invalid_channel

# 4. Insert a malicious row (as ops via service_role) and verify it doesn't cross channels:
# insert (channel='android', version_code=99, apk_url='https://attacker.com/malware.apk')
# Web client should NOT see this row.
```

---

## PR-E — documents-sync: cross-project/cross-investor uniqueness (P1)

**Addresses:** E-6 (P1), E-7 (P2)
**Files touched:**
- `supabase/migrations/20260617000000_065_documents_zoho_file_id_uniq.sql` (NEW)
- `supabase/functions/documents-sync/index.ts`

**The bug:** a Zoho `attachment.id` is global across all of Zoho CRM, not scoped to one LLP. If the same file is attached to two LLPs, the second sync silently overwrites the `project_id` of the first row.

**The fix:**

### 1. New migration: `20260617000000_065_documents_zoho_file_id_uniq.sql`

**VERIFIED:** Migration 055 (`20260608000000_055_project_documents_zoho_file_id.sql`) is a **partial UNIQUE INDEX** on `(zoho_file_id) WHERE zoho_file_id IS NOT NULL` — the index name is `project_documents_zoho_file_id_key`. This is a single-column index, not a composite. E-6 is **confirmed real**: cross-project reuse flips the project_id.

```sql
-- 1. Drop the old single-column partial unique index.
DROP INDEX IF EXISTS public.project_documents_zoho_file_id_key;

-- 2. Replace with a composite partial unique index: same file can
-- be attached to multiple projects, but each (project, file) tuple
-- is unique. Still partial so NULL zoho_file_id (manual uploads) is fine.
CREATE UNIQUE INDEX IF NOT EXISTS project_documents_project_zoho_file_id_uniq
  ON public.project_documents (project_id, zoho_file_id)
  WHERE zoho_file_id IS NOT NULL;

-- 3. Same fix for the per-investor documents table (also partial, on
-- zoho_file_id alone currently — verified in repo). Drop and recreate
-- as composite. NOT VALID lets the migration apply instantly; VALIDATE
-- in a follow-up after ops reviews duplicates.
ALTER TABLE public.documents
  DROP CONSTRAINT IF EXISTS documents_zoho_file_id_key;
CREATE UNIQUE INDEX IF NOT EXISTS documents_investor_zoho_file_id_uniq
  ON public.documents (investor_id, zoho_file_id)
  WHERE zoho_file_id IS NOT NULL;
```

> Note: if your live DB has the single-column UNIQUE named differently (e.g. `documents_zoho_file_id_key` vs the index-named form), adjust the DROP. Use `\d+ documents` in psql to confirm.

### 2. Modify `documents-sync` to handle 23505 with an UPSERT
```ts
// In supabase/functions/documents-sync/index.ts around line 237-249
// (the project_documents upsert), change to:

await supabase.from("project_documents").upsert(
  {
    project_id: project.id,
    storage_path: storagePath,
    title: att.File_Name,
    category: categoryFor(att.File_Name),
    zoho_file_id: att.id,
    is_public: false,
    sort_order: order++,
    uploaded_at: new Date().toISOString(),
  },
  {
    onConflict: "project_id,zoho_file_id",  // <-- composite
    ignoreDuplicates: false,                  // <-- update existing row, don't skip
  },
);
```

And in PART B (line 295-305, the `documents` insert), change `insErr.code !== "23505"` to surface the violation AND log the investor + file:
```ts
if (insErr && insErr.code !== "23505") {
  console.warn(`Doc insert failed (${att.id}) for investor ${inv.id}: ${insErr.message}`);
  continue;
}
if (insErr?.code === "23505") {
  console.warn(`Doc UNIQUE violation (cross-investor file): zoho_file_id=${att.id} investor=${inv.id}`);
}
```

**Rollback:** `git revert` the migration + the function changes. UNIQUE constraint is cheap to drop, but you'll re-introduce the bug.

**Manual verify after deploy:**
```sql
-- 1. Manually attach the same Zoho file to two different projects in the test env.
--    (use the test Zoho sandbox)
-- 2. Wait for documents-sync to run.
-- 3. Verify there are TWO rows in project_documents, one per project, with the
--    same zoho_file_id.
-- 4. Verify the storage object exists at project/<project_a>/<file> AND
--    project/<project_b>/<file> (or the migration set the path with a project prefix).
--    If the path is the same, the second upload will fail with "already exists" —
--    that's fine, the function tolerates it, the DB row gets the right project_id.
```

---

## PR-F — split CRON_SECRET per function (P2)

**Addresses:** E-8 (P2)
**Files touched:**
- 6 Edge Functions: `gallery-sync`, `documents-sync`, `zoho-reconcile-daily`, `health-check`, `sync-stale-alert`, `notify-consultation-request`
- 2 migrations that read `vault.secrets.cron_secret`: `014_enable_pg_cron_and_schedule`, `016_gallery_sync_cron_shared_secret`, `024_schedule_reconcile_and_alert`, `037_consultation_slack_trigger`, `056_documents_sync_cron`
- `supabase/functions/README.md` — update the secrets table

**The problem:** all 6 cron functions use the same `CRON_SECRET` env var and the same `x-arl-cron-secret` request header. One leak compromises all 6. `documents-sync` and `notify-consultation-request` are the most dangerous (storage + Slack).

**The fix:**

1. **Generate 6 new secrets** in Supabase Vault:
   ```sql
   -- Run once, in psql
   select vault.create_secret(
     encode(gen_random_bytes(32), 'hex'),
     'cron_secret_gallery'
   );
   -- ... repeat for documents, reconcile, health, alert, consult
   ```

2. **Set the env vars on each function**:
   ```bash
   supabase secrets set CRON_SECRET=$(vault read -field=value cron_secret_gallery) --no-verify-jwt
   supabase secrets set CRON_SECRET=$(vault read -field=value cron_secret_documents)   --no-verify-jwt
   # ... etc
   ```

3. **Update each function's code** to read its own env var. Two options:
   - **Option A (smallest diff):** keep reading `CRON_SECRET` but set DIFFERENT values per function via the CLI above. The function code is unchanged; the secret per function is the env var, but the var name is the same. **Net effect: same code, different secrets.** The compromise blast radius is still "one secret = one function" because the secrets are different values. **This is the recommended quick fix.**
   - **Option B (cleaner):** rename each function's env var to `CRON_SECRET_GALLERY`, `CRON_SECRET_DOCUMENTS`, etc., and update the code. More work, more verbose, no security benefit over Option A.

4. **Update the cron migrations** to read the per-function vault secret:
   ```sql
   -- Example for documents-sync (migration 056):
   SELECT cron.schedule('documents-sync-daily', '45 0 * * *', $$
     SELECT net.http_post(
       url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/documents-sync',
       headers := jsonb_build_object(
         'Content-Type', 'application/json',
         'x-arl-cron-secret',
           (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'cron_secret_documents')
       ),
       body := '{}'::jsonb
     );
   $$);
   -- Repeat for the other 5 cron jobs.
   ```

5. **Manual rotation schedule:** add a calendar reminder to rotate all 6 secrets every 90 days. The reminder can live in `.claude/decisions/`.

**Rollback:** `git revert` all the function code changes + the migration changes + restore the env vars. The function will work the same; only the rotation is undone.

**Manual verify after deploy:**
```bash
# 1. Verify the OLD shared secret no longer works on documents-sync:
curl -X GET -H "x-arl-cron-secret: $OLD_SHARED_SECRET" \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/documents-sync
# expect: 401

# 2. Verify the NEW per-function secret works:
curl -X GET -H "x-arl-cron-secret: $NEW_DOCS_SECRET" \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/documents-sync
# expect: 200

# 3. Verify the gallery secret does NOT work on documents-sync (cross-function test):
curl -X GET -H "x-arl-cron-secret: $NEW_GALLERY_SECRET" \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/documents-sync
# expect: 401

# 4. Wait 24h, verify both cron jobs ran (check webhook_log)
```

---

## PR-G — sync-stale-alert: de-duplicate alerts (P2)

**Addresses:** E-9 (P2)
**Files touched:**
- `supabase/functions/sync-stale-alert/index.ts`
- NEW migration: `supabase/migrations/20260618000000_066_sync_alerts_dedup.sql`

**The problem:** every hourly run that finds a stale table inserts a NEW `sync_alerts` row. Over a 6-hour outage on `investor_units`, that's 3 duplicate alerts; over a 24-hour outage on `llps`, 4 duplicates. Alert fatigue.

**The fix:**

### 1. New migration: `20260618000000_066_sync_alerts_dedup.sql`
```sql
-- Add a unique on (table_name) so only ONE open alert can exist per table.
-- Resolved alerts can be re-inserted for a new outage.
ALTER TABLE public.sync_alerts
  ADD CONSTRAINT sync_alerts_table_name_uniq
  UNIQUE (table_name);
-- NOT VALID: existing duplicates need a one-time cleanup; the function will dedup going forward.
```

### 2. Modify `sync-stale-alert` to UPSERT and track resolved state
```ts
// In supabase/functions/sync-stale-alert/index.ts, replace lines 83-99

for (const r of rows ?? []) {
  const t = r.table_name as string;
  // ... existing computation of ageSeconds, threshold, stale ...
  summary.push({ table: t, rows: ..., age_seconds: ageSeconds, threshold, alert: stale });
  if (stale) {
    // UPSERT: if an open alert exists for this table, refresh its
    // last_seen_at; otherwise insert.
    const { error: alertErr } = await supabase
      .from("sync_alerts")
      .upsert(
        {
          table_name: t,
          max_synced_at: r.max_synced_at,
          age_seconds: ageSeconds ?? threshold + 1,
          threshold_secs: threshold,
          detail: ageSeconds === null
            ? "no rows have last_synced_at set"
            : `max(last_synced_at) is ${ageSeconds}s old, threshold ${threshold}s`,
          first_seen_at: new Date().toISOString(),  // ignored on update
          last_seen_at: new Date().toISOString(),
        },
        { onConflict: "table_name", ignoreDuplicates: false }
      );
    if (alertErr) console.error(`sync_alerts upsert failed for ${t}: ${alertErr.message}`);
  } else {
    // Table is fresh. Delete any open alert for it.
    const { error: delErr } = await supabase
      .from("sync_alerts")
      .delete()
      .eq("table_name", t);
    if (delErr && delErr.code !== "PGRST116") {
      console.error(`sync_alerts delete failed for ${t}: ${delErr.message}`);
    }
  }
}
```

You'll also need migration steps to add `first_seen_at` and `last_seen_at` columns (not shown in the snippet; one-line ALTER).

**Rollback:** `git revert` the function changes + drop the unique constraint.

**Manual verify after deploy:**
```bash
# 1. Force a stale state: set investors.last_synced_at to 25h ago.
psql -c "UPDATE investors SET last_synced_at = NOW() - INTERVAL '25 hours' WHERE id = '<TEST_INVESTOR_UUID>';"

# 2. Trigger sync-stale-alert manually:
curl -X POST -H "x-arl-cron-secret: $CRON_SECRET_ALERT" \
  https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/sync-stale-alert
# expect: 200 with one alert for "investors"

# 3. Trigger again 1 minute later.
# expect: 200, still one alert for "investors" (last_seen_at advanced, count unchanged)

# 4. Restore investors.last_synced_at and trigger again.
psql -c "UPDATE investors SET last_synced_at = NOW();"
curl -X POST .../sync-stale-alert
# expect: 200, zero alerts for "investors" (the alert was deleted)
```

---

## PR-H — repo + ops cleanups (P3 bundle)

**Addresses:** E-12 (P3), E-14 (P3), E-15 (P3), E-16 (P3), E-17 (P3)
**Files touched:**
- `lib/core/repositories/consultation_requests_repository.dart` (E-12)
- `lib/core/repositories/projects_repository.dart` (E-14)
- `supabase/functions/zoho-reconcile-daily/index.ts` (E-15)
- `supabase/migrations_archive_20260608/20260513000100_035_sync_status_security_invoker.sql` (E-16) — actually edit the live schema via new migration
- `lib/core/repositories/exit_requests_repository.dart` (E-17 — backfill comment)
- `.claude/decisions/` — log the rationale for each

**Changes:**

### E-12 — consultation_requests_repository.dart
```dart
// Line 18 — change from:
final uid = client.auth.currentUser!.id;
// to:
final uid = ArlSupabase.currentUserId;
if (uid == null) {
  throw StateError('Not signed in — cannot create consultation request.');
}
```

### E-14 — projects_repository.dart
Drop the redundant `.inFilter('id', ids)` on line 73 and `.isFilter('deleted_at', null)` on line 74, since RLS already enforces both. The repository comment should be updated to match the style in `investor_repository.dart:48-57`:
```dart
// RLS filters projects to (is_listed_in_marketplace = true
//   OR id IN (SELECT project_id FROM investor_units WHERE investor_id = auth.uid()))
// AND deleted_at IS NULL. No Dart-side filter needed.
final rows = await client.from('projects').select();
```
(If you're risk-averse, leave the filters in — they're defense-in-depth and harmless.)

### E-15 — zoho-reconcile-daily: add a PII-safety comment
Insert a comment block above the `webhook_log` insert at line 490-498:
```ts
// IMPORTANT: the payload below is consumed by health-check (counts only) AND
// is visible to anyone with service-role access (the webhook_log table is
// service-role-only). NEVER include PII fields (name, email, phone, PAN,
// bank account) in the payload — even the *counts* of updated rows are
// fine, but not the rows themselves. If you need to log per-row data for
// debugging, use a separate, redacted audit log with a tighter access policy.
```

### E-16 — sync_status view: clarify the security posture in a new migration
```sql
-- 20260619000000_067_sync_status_doc_posture.sql
-- The sync_status view is service-role-only by intent (all consumers are
-- cron functions running with the service-role key). When security_invoker
-- = on (set by migration 035), an authenticated investor calling this view
-- would see RLS-scoped counts (1 row for investors, 0 for llps), which is
-- misleading. The view IS NOT exposed to investors today, but the COMMENT
-- alone wasn't enough to prevent a future contributor from wiring it to
-- the home dashboard. Add a hard guard: revoke SELECT from authenticated
-- and anon so even a misconfigured future caller gets 0 rows.
revoke select on public.sync_status from anon, authenticated;
-- service_role retains access via the GRANT ALL FROM 019.
```

### E-17 — exit_requests: log the backfill decision
Add a comment to `lib/core/repositories/exit_requests_repository.dart`:
```dart
// NOTE: the 5-year lock-in (migration 044) requires investor_units.investment_date
// to be non-NULL. Rows with NULL investment_date will fail the lock-in RLS
// check and the user will see a confusing "you can't exit" message even
// after 5+ years. Ops needs to backfill investment_date from Zoho's
// Investment_Date field for any rows that pre-date the column being
// non-null. Tracked in .claude/decisions/2026-06-13_e17_investment_date_backfill.md.
```

**Rollback:** `git revert` is straightforward for all of these.

---

## How to ask Claude Code to execute this plan

If you want to delegate to Claude Code, paste this prompt:

```
I have a security remediation plan for the ARL Growize app. The plan is at
docs/security/REMEDIATION_PLAN_AGENT_E.md — please read it and execute
PR-A first (bank-change-request input validation + KYC gate). PR-A is
P0 severity and independent of the other PRs.

Working directory: C:\Users\Sahil\Downloads\ARL\arl_app

Conventions:
- Use the project's existing branch-and-PR workflow.
- One commit per PR with a Conventional Commits message (feat/bank-change: ...).
- After the code change, run the manual verification steps in the plan
  (they're listed at the end of each PR).
- If a verification step fails, STOP and report. Do not paper over it.

Stop after PR-A. Do not start PR-B without my sign-off.
```

Then for each subsequent PR, paste a similar prompt. The plan is structured so each PR is **independently shippable** — if one breaks prod, you can revert it without losing the others.

---

## Timeline expectation

Assuming one focused work day per PR (8 hours):

| PR | Severity | Effort | Calendar week |
|----|----------|--------|---------------|
| A  | P0 | 0.5 day  | Week 1, Mon |
| B  | P0 | 1.5 days (new fn + Flutter) | Week 1, Tue-Wed |
| C  | P1 | 0.25 day (1-line fix) | Week 1, Thu |
| D  | P1 | 0.5 day  | Week 1, Fri |
| E  | P1 | 0.5 day  | Week 2, Mon |
| F  | P2 | 1 day    | Week 2, Tue |
| G  | P2 | 0.5 day  | Week 2, Wed |
| H  | P3 | 0.5 day  | Week 2, Thu |

**Total: ~5 engineer-days, 2 calendar weeks. Ship PR-A and PR-B this week — they are the actual account-takeover mitigation; everything else is hardening.**

---

## What I did NOT cover (out of Agent E's scope)

- **Flutter UI changes for PR-B** (OTP entry modal) — I described the contract; you/your designer should mock the flow.
- **Penny-drop verification for bank change** — mentioned in PR-B's note as a future hardening. Out of scope here.
- **Migration 055's exact constraint name** — I used a placeholder in PR-E. Read 055 first to confirm before shipping.
- **CORS / email-bombing / XSS findings** — covered by other agents. PR-A's length cap partially overlaps with Agent A's email-bombing surface for the bank-change ops email.

---

## Anomalies discovered while writing the plan (READ FIRST before executing any PR)

These were found during re-verification for the execution pass. They do **not** change the PR shapes but they DO change the code you ship. If you skip this section, the patches won't apply.

### A-1. `notify-bank-update` Edge Function does not exist
**Location:** `lib/features/profile/bank_details_screen.dart:374`
The Flutter bank-change flow calls `client.functions.invoke('notify-bank-update', ...)` as a fire-and-forget side effect — but the function is **not in `supabase/functions/`**. Either it was deleted in a refactor, or it was never shipped. The call silently fails (Fire-and-forget means no error is surfaced). PR-A should NOT fix this — it's a dead call. **Recommend filing a separate low-priority issue to either implement `notify-bank-update` or remove the dead call.**

### A-2. Migration 055 is a partial UNIQUE INDEX, not a CHECK constraint
**Location:** `supabase/migrations_archive_20260608/20260608000000_055_project_documents_zoho_file_id.sql:28-30`
The constraint is a partial UNIQUE INDEX named `project_documents_zoho_file_id_key` on `(zoho_file_id) WHERE zoho_file_id IS NOT NULL`. PR-E's migration must use `DROP INDEX` (not `DROP CONSTRAINT`). Already corrected in the PR-E body above.

### A-3. `kyc_status` enum has 4 values, not 3
**Location:** `supabase/migrations_archive_20260608/20260411074801_002_core_tables_investors_projects.sql:31`
CHECK is `IN ('pending','in_progress','verified','rejected')`. The PR-A KYC gate uses `'verified'` — correct. No code change needed, just confirming.

### A-4. `account_masked` format is `XXXX-XXXX-1234` (not `XXXX-1234` or `XXXX-XXXX-XXXX-1234`)
**Location:** `lib/features/auth/setup_screen.dart:179`, `lib/features/profile/bank_details_screen.dart:415`
The Flutter client produces `XXXX-XXXX-${last4}` (one block of X's, one hyphen, another X-block, hyphen, 4 digits). The Edge Function's `isAlreadyMasked` regex `/^X+(-X+)*-\d{4}$/` accepts this. PR-A does not need to change the regex.

### A-5. The `dashboard` route — `kIsWeb` import is needed for PR-D
**Location:** `lib/core/repositories/app_config_repository.dart` (current file is 14 lines)
The current `AppConfigRepository` is tiny and does not import `kIsWeb` or `defaultTargetPlatform`. PR-D's planned `_detectChannel()` helper will need to add these imports. The Claude Code prompt for PR-D must mention this.

### A-6. `documents-sync` cross-investor (PART B) has a DIFFERENT bug from PART A
**Location:** `supabase/functions/documents-sync/index.ts:270-275`
PART A's `existing` SELECT scopes by `project_id` (correct for the bug there). PART B's `existing` SELECT scopes by `investor_id` (also correct). Both queries miss the GLOBAL zoho_file_id UNIQUE the live DB enforces — so if two investors have the same Zoho attachment, PART B's insert fails with 23505 and the `if (insErr && insErr.code !== "23505")` block swallows it (line 307). The silent swallow IS the bug. PR-E's fix is correct; flag this so the implementing agent doesn't miss the swallow line.

---

*Plan written by Agent E (Hermes). 15 actionable findings, 8 atomic PRs, 5 engineer-days estimated. 6 anomalies logged. No code modified — plan only.*
