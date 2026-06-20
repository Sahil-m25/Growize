# arl_app — Final Security & Production-Readiness Audit

**Repo:** `C:\Users\Sahil\Downloads\ARL\arl_app`
**Date:** 2026-06-12
**Method:** Six parallel audit agents (DDoS · prompt-injection · secrets · hygiene · RLS/edge-fn · auth) + targeted follow-up reads. Source-review only, no dynamic testing.

**Total findings:** 35 (from the first pass) + 26 (D) + 17 (E) = **78 findings**.

---

## 1. Security flaws (12 items — fix before ship)

These are the findings that let an attacker in. P0 active exploits first, then P1 chain components, then secondary P1s.

### P0 — actively exploitable (7)

#### S-1. `.env` is bundled as a Flutter asset, shipping in the release APK
- **Where:** `pubspec.yaml:97` (`assets: - .env`); `lib/main.dart:74-82` (runtime guard contradicts the asset declaration).
- **Problem:** The `.env` is packaged into `flutter_assets/.env` in every release APK. `unzip` extracts it in 5 seconds. Today the file holds the Supabase URL, anon JWT, Sentry DSN, and `ARL_AUTH_GATE_SECRET`. The anon key is by design public, but the bundle will silently ship any future high-value secret added to `.env`.
- **Fix:** Remove `- .env` from `pubspec.yaml:97`. For dev, use `--dart-define-from-file` only. Add a CI check (`unzip -l app-release.apk | grep -q '\.env$' && exit 1`).

#### S-2. `ARL_AUTH_GATE_SECRET` is shipped in the client binary
- **Where:** `.env`; `lib/core/constants/supabase_constants.dart:88-91`; sent as `x-arl-cron-secret` from `lib/core/auth/session_manager.dart:56,62-67`.
- **Problem:** 64-char hex HMAC key, intended to gate the `request-auth-email` edge function, baked into `libapp.so` / `main.dart.js`. APK extraction = secret leak. With the secret, an attacker can call `request-auth-email` for any registered email at will and trigger Supabase's email-OTP dispatch → email-bombing of any investor.
- **Fix:** Do not ship a shared secret to the client. Remove `dotenv` fallback for this key. Rotate the committed value. Auth-gate the function via Supabase JWT instead of a client-known secret.

#### S-3. `request-auth-email` CORS is `*` (regression vs every other edge function)
- **Where:** `supabase/functions/request-auth-email/index.ts:27-32`.
- **Problem:** Every other edge function uses the post-audit S-005 allow-list helper from `_shared/cors.ts`. This one still ships `Access-Control-Allow-Origin: *`. It is the only anonymous edge function in the codebase, so CORS is the only line of defense against arbitrary cross-origin abuse.
- **Fix:** Replace the inline `CORS` dict with `corsHeaders(req)` from `../_shared/cors.ts` and set `APP_ALLOWED_ORIGINS` in Supabase secrets.

#### S-4. Real investor + developer PII in committed docs and fixtures
- **Where:** `docs/ops/tickets.md:36,144,276`; `docs/ops/documents.md:238`; `docs/testing/runs/2026-05-07-*.json`; `docs/testing/runs/2026-05-11-uat-walkthrough.md`; `outputs/fill_results.py:13,260`; `outputs/build_tracker.py:122-140`; `docs/testing/fixtures/fixture_payloads.json:15,49-94`; `lib/features/legal/legal_content.dart:17` (compiled into the APK).
- **Problem:** Production investor email `sahil.mohite@agresearchlabs.com` (ARL-002, zoho_contact_id `1169101000001243004`), developer's personal Gmail `sahilmhl25@gmail.com`, and live Zoho record IDs (`1169101000001467016` etc.) committed across docs and fixtures. The legal-content file compiles the production contact email into the APK. DPDP Act concerns: personal data of a real KYC-verified investor is in public-by-default git history.
- **Fix:** Redact to RFC 2606 reserved `.example`/`.test` TLDs. Add a pre-commit `gitleaks` / `trufflehog` hook for `@agresearchlabs.com` and the `1169101` Zoho prefix. Verify investor consent under DPDP. Scrub from history with `git filter-repo` if any real PII is confirmed.

#### S-5. `bank-change-request` has no KYC-verified precondition, no step-up auth (account-takeover pivot)
- **Where:** `supabase/functions/bank-change-request/index.ts:71-186` (deep-read by Agent E).
- **Problem:** A bank-account change is the single highest-value account-takeover pivot — once a new account is on file, future payouts go to the attacker. The function only enforces: (a) `auth.uid()` matches the caller, (b) 7-day cooldown, (c) masked-account regex, (d) `ifsc` regex. It does **not** check `kyc_status='verified'`, does not require a fresh biometric/PIN re-entry, does not require a second factor. An attacker who phishes one OTP or compromises a single password can lock a victim out of their own payouts within 7 days. The masked-account regex is also bypassable (the function stores the *masked* form, not the actual; a victim who enters a wrong account number doesn't know).
- **Fix:** (a) Reject the request if `kyc_status != 'verified'`. (b) Require a fresh biometric/PIN re-auth (call `local_auth` server-side is impossible; instead, the app must submit a `step_up_token` issued by `local_auth` and verified against the `user_settings.app_pin_hash` server-side). (c) Send a confirmation email/SMS to the **previously** registered bank account's last-4 with a "this is correct, click to confirm" link. (d) Validate IFSC against the RBI IFSC list (mirror the JSON, daily refresh). (e) Store the **real** account number (hashed) plus the last-4 for display.

#### S-6. `zoho-crm-webhook` reads request body without a size cap (memory exhaustion)
- **Where:** `supabase/functions/zoho-crm-webhook/index.ts:331-344`.
- **Problem:** `req.text()` buffers the entire body in memory with no `Content-Length` check. The function then `JSON.parse`s and re-`JSON.stringify`s the entire blob for `sanitizeForLogging` (L168-191), tripling peak memory. A leaked `WEBHOOK_SECRET` (or a Zoho compromise) lets an attacker POST 100 MB and exhaust the Edge Function worker's 256 MB heap.
- **Fix:** Reject `Content-Length > 256 KiB`. Stream-parse with a byte counter. Move the sanitise-deep-clone to an iterative pass that doesn't re-stringify.

#### S-7. `app_releases` table is referenced by `latest-app-version` but **never created by any migration**
- **Where:** `supabase/functions/latest-app-version/index.ts:54-96` queries `app_releases`; no migration in `supabase/migrations/` or `supabase/migrations_archive_20260608/` creates this table.
- **Problem:** The function silently returns "no release" today (PostgREST returns an empty result for a missing table in some configurations, or a 404 in others). The day someone adds the table without a `channel` column, every user gets an open-redirect to the same global URL regardless of platform (B-1 cascade). This is also why B-1's "actor who can write a row to `app_releases`" path is harder to exploit than it looks — *nobody* can write a row, the table doesn't exist.
- **Fix:** Add a migration `063_app_releases.sql` that creates the table with a `channel` column (`android | ios | web`) and an RLS policy limiting writes to `service_role`. Update `latest-app-version` to filter by `channel`.

---

### P1 — chain components (5)

#### S-8. `app_releases.apk_url` / `web_url` open-redirect with no host allow-list
- **Where:** `lib/core/version/version_banner.dart:36-46`; `lib/core/version/app_version_check.dart:111-117`; `supabase/functions/latest-app-version/index.ts:65-91`.
- **Problem:** URL handed straight to `launchUrl(uri, mode: LaunchMode.externalApplication)` with no scheme/host validation. `isCritical=true` shows a non-dismissible dialog. The OS browser will not prompt before APK download → drive-by malware.
- **Fix:** Allow-list hosts (`play.google.com`, `apps.apple.com`, `arl.app` / `agresearchlabs.com`). Never auto-launch critical. Render destination host on the button. Add a SQL CHECK constraint + RLS so only `service_role` can write.

#### S-9. Web idle-timer can be kept alive by any same-origin script (XSS keeps the session "live" forever)
- **Where:** `lib/main.dart:309-315` (`Listener(onPointerDown: ...)`); `lib/core/auth/web_session_web.dart:19-22`; `lib/main.dart:216-225`.
- **Problem:** `Listener.onPointerDown` fires for any pointer event including `element.dispatchEvent(new PointerEvent('pointerdown'))` from a same-origin script. Combined with S-13 (`flutter_secure_storage_web` stores the session in plain `localStorage`), any future XSS payload can fire `pointerdown` once per minute to keep the session "active" indefinitely **and** read the Supabase refresh token directly. Defeats the entire purpose of the web idle guard.
- **Fix:** Move the idle-reset trigger to a Flutter-side hook (route change / explicit user-action filter). Replace `flutter_secure_storage` on web with `sessionStorage` (tab-scoped). Add a hard cap from the access token's `exp` claim.

#### S-10. `request-auth-email` is unauthenticated, unrate-limited, email-bombing-prone
- **Where:** `supabase/functions/request-auth-email/index.ts:55-160`; `lib/core/auth/session_manager.dart:43-71`.
- **Problem:** No auth check, no shared-secret validation, no per-IP throttle, no per-email cooldown, no body size cap. The `x-arl-cron-secret` header sent by the client is never read. An attacker can drain Supabase edge-invocation quota, email-bomb any registered investor at unbounded rate, or use the timing of the upstream `/auth/v1/otp` call vs. the early-return for soft enumeration.
- **Fix:** Validate `x-arl-cron-secret` in the handler (constant-time). Add per-IP and per-email rate limits (Upstash or `rate_limit_buckets` table). Cap request body size. Reuse the CORS fix from S-3.

#### S-11. `latest-app-version` does not filter by `channel` — returns global latest row regardless of platform
- **Where:** `supabase/functions/latest-app-version/index.ts:65-91`.
- **Problem:** The function returns the latest `app_releases` row without filtering by the caller's `channel` (android/ios/web). Once the table exists (S-7 fix), a single Android-only update row will be served to iOS and web users. Cascades the open-redirect in S-8.
- **Fix:** Accept a `?channel=android|ios|web` query param (the client already knows its platform) and `.eq('channel', channel)`. Default-deny on missing/empty channel.

#### S-12. `documents-sync` Zoho attachment collision can flip a document's `project_id` silently
- **Where:** `supabase/functions/documents-sync/index.ts` (deep-read by Agent E).
- **Problem:** Zoho `attachment.id` is global but the function's `seen` set is scoped per-project. If the same attachment is reused across two LLPs in Zoho, the second sync updates the first row's `project_id` to the new one — the document silently moves between projects in the DB. The signed URL in storage doesn't move, but the DB-level authorization context does. This is a cross-investor authorization context bug: an investor on Project A might lose access to a document they previously had access to, and an investor on Project B might gain access.
- **Fix:** Make the `seen` set global (or key by `(zoho_file_id, project_id)`). Add a check that rejects an existing row whose `project_id` differs from the new sync's `project_id` and emit a Sentry alert.

---

### P2 / P3 (5 secondary items in the security domain)

- **S-13 (P3).** `flutter_secure_storage` on web stores the session in plain `localStorage` — the "secure" prefix is misleading. Add `WebOptions(dbName, publicKey)` to raise the bar.
- **S-14 (P2).** `notify-consultation-request` posts user message to Slack as raw `mrkdwn` (no escaping) — `B-3` already documented.
- **S-15 (P2).** Web CSP allows `'unsafe-eval'` in `netlify.toml:33`.
- **S-16 (P3).** Syncfusion `SfPdfViewer.network` renders PDFs with JS actions enabled by default.
- **S-17 (P3).** No Subresource Integrity (SRI) on `flutter_bootstrap.js`.

---

## 2. What is broken (12 items — functional bugs surfaced by the audit)

These don't fit the security bucket. They are real bugs, latent footguns, or dead code that the audit caught.

#### B-1. `CelebrationTrigger.maybeShow(context, ref)` is never called from production code
- **Where:** `lib/features/celebration/celebration_trigger.dart`; the only reference in `lib/` is a `// TODO` at `home_screen.dart:22`.
- **Impact:** Real users will never see the first-payout celebration overlay. The whole `lib/features/celebration/` feature — route, screen, flag, preview entry — is wired but inert. This is a delivered-but-shipped-as-Demo feature: dead in production.
- **Fix:** Wire the call from `home_screen.dart` after the home provider resolves with a positive payout delta, or delete the feature.

#### B-2. `notify-consultation-request` Slack lookup always returns null ("Unknown investor")
- **Where:** `supabase/functions/notify-consultation-request/index.ts:100-115` (Agent E deep-read).
- **Problem:** The query is `supabase.from('investors').select('name, arl_id, email, phone').eq('user_id', consultation.user_id).maybeSingle()`. The `investors` table has **no `user_id` column** — its primary key is `id = auth.users.id`. The query returns null on every consultation request, and the Slack post always says "Unknown investor". 100% of consultation Slack alerts are silently broken.
- **Fix:** Replace `.eq('user_id', ...)` with `.eq('id', consultation.user_id)`. Also fix any other repository that queries `investors.user_id` (grep: `rg "investors.*user_id" supabase/functions lib/core/repositories`).

#### B-3. `app_releases` table doesn't exist (already documented in S-7) — silent no-op today, crash tomorrow
- (See S-7 above.) Categorising here as a functional bug: `latest-app-version` returns "no release" today, the version-gating screen never shows, force-update never works. Users on a broken build can't be pushed to update.

#### B-4. `lib/app.dart` is a dead 4-line re-export shim
- **Where:** `lib/app.dart:1-4` — `export 'main.dart' show ArlApp;`. Zero callers in `lib/`.
- **Fix:** Delete the file, or merge `main.dart` and `app.dart` and update the few import sites.

#### B-5. `lib/features/celebration/preview_entry.dart` is unused
- The `CelebrationPreviewEntry` widget is never imported. The profile screen inlines a duplicate `_menuTile` with the same route string. Dead code that will drift.

#### B-6. `docs/MAINTENANCE_HANDOVER.md` references 11 deleted docs
- **Where:** `docs/MAINTENANCE_HANDOVER.md` cites `data_flow_guide.md`, `debug_runbook.md`, several `e2e_test_results_*.md`, `parity_patches_2026-05-11.md`, etc. All 11 are in `git status` as `D` (deleted in working tree, not yet committed).
- **Impact:** Broken links for any new maintainer. The handover doc is half-broken until the deletions are committed.
- **Fix:** Either commit the deletions (`git add -u docs/`), or update the handover doc to point at the replacement docs (if any).

#### B-7. `flutter_dotenv` loads `.env` in `release` when `kReleaseMode` is true even though the team documented it shouldn't
- **Where:** `lib/main.dart:74-82`. The `dotenv.load` call runs on native (Android/iOS) in release mode. The `.env` is in the asset bundle. This is S-1 in security terms, but it's also a *behavioural* bug: the team intended `--dart-define` to be the only path, but the runtime fallback defeats the intent.
- **Fix:** In `kReleaseMode`, `throw StateError` if `dotenv` is loaded (mirror the existing `devBypassAuth` check on line 89-91).

#### B-8. `signInWithRefreshToken` is dead code
- **Where:** `lib/core/auth/session_manager.dart:97-100`; `lib/core/auth/secure_session_store.dart:13,21,28-34`; `lib/core/auth/biometric_screen.dart` is a UI gate over a session that was never lost. The refresh token is being persisted to `flutter_secure_storage` on every `signedIn` / `tokenRefreshed` (Agent F F-5) but no screen ever reads it back. Unnecessary data-at-rest, misleading documentation.

#### B-9. `tutorial_overlay.dart` and `tutorial_provider.dart` are empty stubs
- **Where:** `lib/features/onboarding/tutorial_overlay.dart`; `tutorial_provider.dart`. Zero callers. Their own headers say "Legacy — replaced 2026-05-21" and `.claude/decisions/2026-05-21_tour_rewrite.md` confirms. Tripwire-by-comment, not by import. P3 only — confusing for new contributors.

#### B-10. 12 of 19 git worktrees are currently modified, 1.2 GB total, none gitignored
- **Where:** `.claude/worktrees/*` (19 dirs, 1.2 GB; `busy-wilbur-45c6e6` alone is 1.2 GB; 12 show as `M` in `git status`).
- **Impact:** Clutters `git status` for every developer. A future `git add -A` will stage 1.2 GB of noise. Worktrees are runtime artefacts, not source.
- **Fix:** Add `.claude/worktrees/` to `.gitignore`. `git worktree prune` the ones that are no longer needed.

#### B-11. `bank-change-request` masked-account regex accepts short / wrong-format numbers and stores only the masked form
- **Where:** `supabase/functions/bank-change-request/index.ts` (Agent E).
- **Problem:** The function stores the *masked* account number (`XXXX-XXXX-9012`), not the real one. A victim who typoed their account number has no way to discover the typo via the UI. Ops sees a masked value, so the only verification channel is a manual callback. This is also why E-1 is a P0: a wrong account number typed by a phisher or a careless user is the silent path to lost payouts.
- **Fix:** Store the real account number (hashed with a per-investor key, plus the last-4 for display). Validate length (9-18 digits) and a `modulus`/`luhn`-style check for the bank identifier.

#### B-12. `graphify-out/` (~1.2 MB of regenerable tool output) is tracked
- `graphify-out/cost.json`, `graph.json`, `GRAPH_REPORT.md` — re-generable, tracked, pollutes git history and the agent context window on every search.
- **Fix:** Add to `.gitignore`. Regenerate locally as needed.

---

## 3. What makes it less production-ready (12 items — release blockers, ops gaps, observability)

Not bugs per se, but things that should be true before this is a real production app that real investors rely on.

### Release blockers

#### R-1. Migrations are split: 5 in `migrations/`, 57 in `migrations_archive_20260608/`
- **Where:** `supabase/migrations/` has 058-062 (the recent 5); `supabase/migrations_archive_20260608/` has 001-057. The README explains the boundary (2026-04-27 backend audit materialised the historical state from the live DB) but the directory split is non-obvious to a new engineer.
- **Impact:** `supabase db reset` + `supabase db push` against a clean checkout will fail or produce a broken schema. Disaster-recovery scenario is fragile.
- **Fix:** Either consolidate into `migrations/` in chronological order with a `00_archive_README.md` explaining the historical boundary, or add a `MIGRATIONS_POLICY.md` to the repo root.

#### R-2. `analysis_options.yaml` has zero lints enabled beyond the `flutter_lints` baseline
- **Where:** `analysis_options.yaml`. Missing on a Supabase-heavy async app: `discarded_futures`, `unawaited_futures`, `avoid_print`, `use_build_context_synchronously`, `cancel_subscriptions`, `close_sinks`. A missing `await` on a Supabase mutation is a silent data-loss bug; the team has explicit examples in their own redteam suite but the lint isn't enforcing it.
- **Fix:** Add the missing lints. Treat the warnings as errors in CI.

#### R-3. CI is one workflow (`deploy-web.yml`) — no PR lint, no `flutter test`, no `flutter analyze`
- **Where:** `.github/` directory.
- **Impact:** A breaking change to a repository can be merged without any automated test. The 3 Dart tests in `test/` and the 8 redteam shell scripts in `tests/redteam/` are run manually (per the `tests/redteam/README.md`'s "Run the full suite on the production Supabase project to verify security gates hold").
- **Fix:** Add a PR workflow that runs `flutter test` + `dart analyze` + the redteam suite on every PR. The redteam suite already has a `run-all.sh` — wire it.

### Observability

#### R-4. Sentry is configured but the scrubber is missing test coverage for the user field
- **Where:** `lib/core/observability/sentry_config.dart:100-136`; `test/sentry_scrub_test.dart:1-105`. Tests cover `scrubText` (string rules) but not `scrubPii` with a `SentryEvent(user: SentryUser(id: ...))` fixture. `main.dart:172-181` sets the user on sign-in. UUID isn't strict PII, but a future regression in `scrubPii` would not be caught.

#### R-5. No structured logging anywhere — all diagnostic output is `console.log` from edge functions and `print` from Dart
- **Where:** Every edge function. Examples: `console.error("[request-auth-email] investor lookup failed", lookupErr);` on `index.ts:105`. The Sentry init in main.dart captures unhandled exceptions but the happy-path "we sent an OTP for investor X" log is just stdout.
- **Impact:** When an incident happens, you can't grep your way through it. The redteam suite has 0% structured log coverage for assertions like "this rate-limit was hit".
- **Fix:** Adopt a small structured logger (`console.log(JSON.stringify({level, msg, ...ctx}))` is fine) and a Dart `package:logging` setup with JSON output.

#### R-6. Sentry is wired into 6 of 13 edge functions but `Sentry.captureException` is called ad-hoc, not on every error path
- `zoho-crm-webhook` captures only inside the catch block (L451-454). `health-check` does the same. `create-ticket` same. But other functions (`reply-ticket`, `documents-sync`, `gallery-sync`, `bank-change-request`, `notify-consultation-request`) don't initialize Sentry at all. Inconsistent.

### Operational hygiene

#### R-7. Five committed `.xlsx` workbooks at repo root and `outputs/`
- (See Agent C C-5.) `ARL_Test_Tracker.xlsx` (111 KB), `docs/ARL_Growize_Test_Cases.xlsx`, `docs/compliance/ARL_Growize_Data_Inventory_RoPA.xlsx` (this one is meant to be tracked), `outputs/ARL_Test_Tracker_pre_v31_fix.xlsx`, `outputs/ARL_Test_Tracker_pre_visual_check_v2.xlsx`. Test trackers, by their nature, contain real test data including PAN/Aadhaar/bank rows.
- **Fix:** `*.xlsx` in `.gitignore` with explicit `!docs/compliance/ARL_Growize_Data_Inventory_RoPA.xlsx` exception. `git rm --cached` the four. If real PII is confirmed, scrub from history.

#### R-8. 18 markdown files at repo root
- 4 outreach (`outreach_2026-04-30.md`, `outreach_2026-04-30_test.md`, `eka_outreach_tone_guide.md`, `cp_outreach_formula_spec.md`), 2 Jhalak (`jhalak_cowork_setup.md`, `jhalak_gsheet_guide.md`), 1 setup (`setup_outreach_formulas.gs` at root), 1 stray `supabase login/` subdir, plus 5 Google Apps Script / Sheets docs. This is one person's external-tool documentation that leaked into the project root.
- **Fix:** Move to `docs/internal/` or `docs/history/`. Add `.gitignore` for `setup_outreach_formulas.gs` if it's truly transient.

#### R-9. Pinned `^` versions for key packages, 12+ months old in resolved form
- `go_router 14.8.1` (Aug 2024), `flutter_riverpod 2.6.1` (Sep 2024), `intl 0.19.0` (Sep 2024), `flutter_secure_storage 9.2.4` (Aug 2024). `^` ranges allow newer minors but `pubspec.lock` resolves to old. Some of these have known-bad ranges (the auditor is out of scope for CVE check).
- **Fix:** Run `flutter pub upgrade --major-versions` in a controlled PR. Verify each major bump against the changelog.

#### R-10. Two test harnesses (`test/` and `tests/redteam/`) undocumented
- `test/` is the standard `flutter test` discoverable directory. `tests/redteam/` is a separate shell-script harness with its own `setup.sh` and `run-all.sh`. `CLAUDE.md` and `MAINTENANCE_HANDOVER.md` only mention the standard `test/`. A new contributor who reads the handover doc won't discover the redteam suite.
- **Fix:** Add a `tests/README.md` that explains the split and points at `run-all.sh`.

#### R-11. `docs/compliance/` has 6 .docx files with no README index
- `ARL_Growize_Change_and_Compliance_Record.docx`, `ARL_Growize_Data_Inventory_RoPA.xlsx`, `ARL_Growize_DPDP_Action_Plan.docx`, `ARL_Growize_DPDP_Audit_Report.docx`, `ARL_Growize_DPDP_Compliance_Mapping.docx`, `ARL_Growize_DPDP_Compliance_Pack.docx`, `ARL_Growize_DPDP_Templates.docx`. Six binary compliance artifacts, no `README.md` explaining what each is, who owns it, or when it was last reviewed. DPDP Act compliance requires demonstrable governance — undated binary files in a git repo don't help.

#### R-12. `web/` has no `404.html` / `offline.html` and no service-worker recovery story beyond `flutter_service_worker.js`
- For a PWA targeting agri-investors on patchy rural networks, the offline experience is part of the product. The current build will show a blank page if the SW fails to install. (The `docs/PWA_INSTALL_GUIDE.md` documents install, not offline behaviour.)

---

## What is NOT broken (so you can stop worrying about it)

- **No `.env` in git history** (`git log --all --full-history -- .env` is empty).
- **No committed keystores / `key.properties`**.
- **No `.vscode/`.** `.gemini/settings.json` and `.claude/settings.local.json` contain no API keys.
- **Flutter `Text()` is the only render surface** for user-supplied free text. No `HtmlWidget`, `flutter_html`, `flutter_markdown`, `WebView`, or `dart:html` imports anywhere.
- **RLS is enabled on every table** (verified migration 009: all 14 tables).
- **`create-ticket` 5/24h rate limit** is correctly server-side; body capped at 200/5000 chars; category enum validated.
- **`bank-change-request` 7-day cooldown** is enforced server-side.
- **Constant-time secret compares** present in 4+ edge functions.
- **PII masking in `zoho-crm-webhook`** happens before `webhook_log.payload` write.
- **Migration 060** revokes `EXECUTE` on all `SECURITY DEFINER` trigger functions from `public, anon, authenticated`.
- **Migration 062** wraps `auth.uid()` in `(select auth.uid())` (initplan pattern).
- **Migration 061** retention purge is a real `DELETE FROM`, not soft-delete.
- **`sendDefaultPii: false`** on Sentry in `lib/main.dart:129`.
- **`flutter_secure_storage` is genuinely backed by Keystore/Keychain on Android/iOS** (the "secure" prefix is wrong on web only).
- **Zoho OAuth service** is a 3-line stub, not a shipped OAuth flow.
- **`devBypassAuth` in release** is asserted-false in `lib/main.dart:89-91`.
- **Constant-time PIN compare** is a correct XOR-and-OR implementation.

---

## Final production-readiness score: **62 / 100**

### How the score breaks down

| Dimension | Weight | Score | Notes |
|---|---|---|---|
| **Backend security (Supabase + Edge Functions)** | 25 | 18 | RLS good, SECURITY DEFINER revoked, PII masked, constant-time compares, rate limits on most paths. But: S-1, S-2, S-3, S-4, S-5, S-6, S-7, S-10, S-11, S-12 are all P0/P1 in this dimension. Drops the score by 7 points. |
| **Auth / session / lock** | 15 | 10 | S-9 (XSS keeps session live), weak PIN KDF, `biometricOnly:false`, dead `signInWithRefreshToken`, Sentry user-field gap. Each is a P1-P3. |
| **Client security (Flutter + web CSP)** | 10 | 6 | S-1 (env bundled), S-13 (localStorage), B-7 (release uses .env), S-15 (CSP), S-16 (PDF JS), S-17 (no SRI). |
| **Secrets / PII / repo hygiene** | 15 | 7 | S-4 (real PII committed), 19 worktrees at 1.2 GB not gitignored, 5 .xlsx tracked, 18 root-level .md files, 367 KB HTML prototype at root, `app_releases` referenced but never created. |
| **Functional correctness** | 15 | 8 | B-1 (celebration dead), B-2 (consultation Slack always "Unknown"), B-3 (app_releases missing), B-8 (dead refresh-token path), B-9 (empty tutorial stubs), B-11 (bank-change stores masked only). |
| **Operational readiness (CI, observability, migration source-of-truth, doc sprawl)** | 15 | 8 | R-1 (migrations split), R-2 (no lints), R-3 (one workflow, no PR CI), R-5 (no structured logs), R-10 (two test harnesses), R-11 (6 .docx with no index). |
| **Bonus / penalty** | 5 | +5 | Good: `flutter_dotenv` web skip, `devBypassAuth` release assert, refresh-token clear on sign-out, comprehensive Sentry PII scrub (with test coverage), CORS allow-list helper in 11/13 functions, webhook_log payload masking. **+5** for the things that *are* done right. |

**62 / 100 = "Beta".** Not production-grade today. The 4 P0s in the security bucket alone are 4 of the 5 items that, if closed, would push this to 75+. Add the P1 chain components and the migration source-of-truth fix and you'd be at 85+.

### What would push this to 90+
1. Close S-1, S-2, S-3, S-4, S-5, S-6, S-7 (all P0) — net +12 points
2. Close S-8, S-9, S-10, S-11, S-12 (all P1) — net +6 points
3. R-1 (migrations split) + R-2 (lints) + R-3 (PR CI) — net +6 points
4. B-1 (celebration dead) + B-2 (consultation Slack) + B-3 (app_releases missing) — net +3 points
5. Strip 1.2 GB of worktrees, .gitignore the 5 .xlsx, redact the real PII — net +3 points

**Total potential: 90-92 / 100.** The remaining 8-10 points are inherent (Flutter `Text()` is HTML-safe by design — no bonus left; web `'unsafe-eval'` is required for canvas-kit; supabase_flutter's auth flow is platform-managed; some compromises are correct).

### What would make it worse
- Shipping without closing the P0s.
- A real investor filing a DPDP complaint (DPDP fines go up to ₹250 Cr for "non-fulfilment of obligations" under §33).
- A single instance of the Zoho webhook secret leaking (no per-IP throttle + delete fan-out = catastrophic).
- `flutter_dotenv` continuing to ship the bundle while the team adds "harmless" keys that are actually sensitive.

---

*End of report. All findings cross-referenced with the agents' raw output in `audit_findings.md` (sections B, D, E, F written by agents; A and C emitted to stdout only; consolidated here).*
