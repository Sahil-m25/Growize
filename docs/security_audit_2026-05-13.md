# Security Audit — 2026-05-13

**Auditor pass:** pre-private-launch hardening review.
**Severity tally:** 1 Critical · 4 High · 5 Medium · 5 Low.
**Scope:** Flutter client (lib/, pubspec.yaml, mobile manifests),
Supabase schema/RLS (migrations 001–029), edge functions
(`supabase/functions/*`), CI/CD, and ops posture.
**Branch this copy was committed on:** `ARL/hopeful-tesla-6f86bc`
(worktree). The original audit was authored on `main`'s working tree
but never committed there. This file is the canonical record going
forward.

---

## Findings

| ID | Severity | Finding | Location | Status | Resolved In |
|----|----------|---------|----------|--------|-------------|
| **S-001** | Critical | `pubspec.yaml` bundles `.env` as a Flutter asset — Supabase URL and anon key shipped to every install, and any secret accidentally appended to `.env` would ride with them. | `pubspec.yaml` (~line 69, assets list) | **Fixed** | `bba6913 chore(config): env-based supabase config, remove hardcoded creds` (launch-readiness pass on `main`) |
| **S-002** | High | `projects.latitude` / `projects.longitude` returned to every authenticated marketplace viewer. Marketplace + explore + project-list repos call `select()` with no column list, so precise coords go to the wire even though the `LocationScreen` privacy policy says raw coords never leave the screen. | `lib/core/repositories/projects_repository.dart` (`from('projects').select()` × 4) | **Fixed** | _filled in by Fix 1 commit below_ |
| **S-003** | High | `public.sync_status` view runs as `SECURITY DEFINER` (Postgres default for views). Owner is `postgres` (BYPASSRLS), so caller's RLS context is ignored. Same shape of issue migration 015 fixed for `portfolio_summary`. | `supabase/migrations/20260507120000_023_last_synced_at_columns.sql` (view defined at bottom of file) | **Fixed** | _filled in by Fix 2 commit below_ |
| **S-004** | High | `anon` role retains default CRUD on tables 026–029 (`user_settings`, `login_events`, `consultation_requests`, `exit_requests`) plus `sync_alerts` from 023. Migration 019's blanket `REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon` ran before these tables existed, so RLS is the only thing blocking access — no defense in depth. | `supabase/migrations/20260427150400_019_revoke_default_grants.sql` (REVOKE was a snapshot) | **Fixed** | _filled in by Fix 3 commit below_ |
| **S-005** | High | All edge functions ship `Access-Control-Allow-Origin: *`. Any origin can invoke them from a browser (mitigated only by JWT or shared-secret on each function). For private launch, allow-list must be explicit. | `supabase/functions/_shared/cors.ts`, `bank-change-request/`, `create-ticket/`, `onboard-investor/`, `reply-ticket/`, `zoho-crm-webhook/` | **Fixed** | _filled in by Fix 4 commit below_ |
| **S-006** | Medium | App PIN hashed client-side with iterated SHA-256 (≈100k rounds) rather than PBKDF2-HMAC-SHA-256 or Argon2id. Offline-brute-forceable if the hash row leaks. | `lib/features/profile/security_screen.dart` (hash routine) | Deferred | post-launch — switch to PBKDF2-HMAC via `cryptography` package, re-hash on next PIN change |
| **S-007** | Medium | "Auto-lock after X minutes" toggle on SecurityScreen is label-only — no inactivity timer wired up. | `lib/features/profile/security_screen.dart` | Deferred | post-launch |
| **S-008** | Medium | No `FLAG_SECURE` on KYC, Bank, or PIN entry screens — Android allows screenshots / recents-preview of sensitive data. | `android/app/src/main/.../MainActivity.kt` (route-aware FLAG_SECURE not implemented) | Deferred | post-launch |
| **S-009** | Medium | Hive offline cache is unencrypted. KYC fields and partial bank info land in plaintext on-device. | `lib/core/offline/hive_cache.dart` | Deferred | post-launch — switch to `HiveAesCipher` with key from secure storage |
| **S-010** | Medium | Refresh token storage backend not confirmed — must verify Supabase JS uses Keychain on iOS / EncryptedSharedPreferences on Android, not raw `SharedPreferences`. | Supabase Dart client default | Deferred | verify before public launch; document in ops |
| **S-011** | Low | `login_events.user_agent` not length-capped / sanitized. Spoofed/oversized UA strings persist as-is. | `lib/core/repositories/login_events_repository.dart` | Deferred | trivial — clamp to 512 chars on insert |
| **S-012** | Low | Logout / PIN-change / biometric-toggle events not written to `login_events`. Audit trail covers sign-in only. | `lib/features/profile/security_screen.dart` | Deferred | post-launch |
| **S-013** | Low | No root / jailbreak detection. | n/a (gap) | Deferred | post-launch — `flutter_jailbreak_detection` |
| **S-014** | Low | Bank account number masking — confirm pattern (last-4 only) is consistent across Profile + Financials + admin email templates. | `lib/features/profile/`, `supabase/functions/_shared/masking.ts` | Deferred | verify in pre-launch QA |
| **S-015** | Low | Quarterly RLS review cadence not documented anywhere. RLS drift is one of the easiest ways to regress data-isolation guarantees. | (gap) | Deferred | add to ops doc Part 7 (Security) — this audit takes first step |

## Posture recommendations (no code change in this pass)

- Quarterly RLS reviews — diff `pg_policies` against the previous quarter, look for new or dropped policies.
- CDN / WAF in front of web build before broader launch (Cloudflare Pages or Vercel free tier are both fine for the static Flutter web build).
- CI grep step that fails the build on `SUPABASE_SERVICE_ROLE_KEY` or `service_role` strings anywhere in `lib/` — service-role keys must never reach a client bundle.
- Focused pentest (authenticated + unauthenticated) before public launch — the 4 High fixes here close the easy paths, but a fresh set of eyes against the running stack will catch logic flaws this audit didn't.

## Remediation status — High fixes (this pass)

| Fix | Finding | Migration | Files | Commit |
|-----|---------|-----------|-------|--------|
| 1 | S-002 coord leak | 034 (`projects_public` view, `security_invoker = on`) | `supabase/migrations/20260513000000_034_projects_public_view.sql`, `lib/core/repositories/projects_repository.dart`, `lib/features/projects/models/project.dart` | _filled in after commit_ |
| 2 | S-003 sync_status DEFINER | 035 (`ALTER VIEW … security_invoker = on`) | `supabase/migrations/20260513000100_035_sync_status_security_invoker.sql` | _filled in after commit_ |
| 3 | S-004 anon CRUD | 036 (`REVOKE ALL FROM anon` on post-019 tables) | `supabase/migrations/20260513000200_036_revoke_anon_post_019.sql` | _filled in after commit_ |
| 4 | S-005 wildcard CORS | n/a (function changes only) | `supabase/functions/_shared/cors.ts`, the 5 edge functions listed above | _filled in after commit_ |

## Apply / verify checklist (ops)

After commits land, an operator must:

1. `supabase db push` — applies migrations 034, 035, 036 to the
   `oynfhdqizebvgmaoiuax` project.
2. For each of the 5 affected edge functions:
   `supabase functions deploy <name>` (one by one). All keep
   `--no-verify-jwt` flags they had before.
3. `supabase secrets set APP_ALLOWED_ORIGINS=https://app.agresearchlabs.com,http://localhost:8080,http://localhost:5000`
   (comma-separated, no spaces; `http://localhost:*` is also recognised
   by the helper for any localhost port during `flutter run -d chrome`).
4. Re-run the Supabase advisor (Studio → Advisors) and confirm:
   - `security_definer_view` warning on `public.sync_status` is gone.
   - `rls_disabled_in_public` / `policy_exists_rls_disabled` clean.
5. `psql` smoke:
   - `SELECT * FROM information_schema.role_table_grants WHERE grantee='anon' AND table_schema='public';` → only `app_config` should appear.
   - `SELECT * FROM pg_views WHERE viewname IN ('projects_public', 'sync_status');` → both list with `security_invoker = on` in `pg_class.reloptions`.
