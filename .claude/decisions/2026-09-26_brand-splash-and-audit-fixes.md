# 2026-09-26 — Branded first-load screen + audit fixes

## Why
Boot showed 3-4 different screens: white/default native splash -> green web
splash with a placeholder SVG -> cream screen with a bare spinner -> green
spinner (lock gate). An audit (flutter analyze, tests, schema + route map)
also found routing and account-switch bugs.

## Loading screen (one continuous screen on every platform)
- New `lib/core/widgets/brand_splash.dart`: cream bg, 72px "g" mark dead-centre,
  "growize / INVESTOR PORTAL", gold indeterminate bar, "by Agri Research Labs".
- Used for the app_config gate load (`main.dart`) and lock-settings load (`_LockGate`).
- `web/index.html` splash rebuilt to match pixel-for-pixel (real logo inlined,
  no 6s force-hide; shows "Reload" after 15s instead of a blank page).
  `manifest.json` background + theme-color -> #FAFAF7.
- Android: `launch_background.xml` (both) = cream + `@drawable/splash_mark`;
  `values-v31` / `values-night-v31` add the Android 12+ SplashScreen API
  (otherwise Android 12+ shows the launcher icon on white/black).
  Night mode keeps brand cream.
- iOS: `LaunchImage*` replaced with the mark (72pt), storyboard bg cream.
- Source asset: `assets/images/splash_mark.png` (trimmed from growize_g.png).

## Code fixes
- router: split `_publicRoutes` from `_signInRoutes` {auth, login}. Signed-in
  users can now open Privacy/Terms (were bounced to Home); OtpScreen is no longer
  yanked away mid-routing (biometric nudge now reachable, back stack clean);
  `/setup` is now private (was public + bounced for signed-in users).
  Refresh notifier disposed.
- main.dart: removed `_ProviderObserver` (added a new onAuthStateChange listener
  per login/logout, never cancelled; invalidations were redundant — all six
  providers watch authStateProvider).
- auth_provider: on signedIn/signedOut clear signed-URL cache + reset project
  filter; on signedOut wipe all Hive boxes (`clearUserCaches`) — cache keys are
  not user-scoped, so user B could see user A's data via offline fallback.
  Sentry user set on cold start too.
- Document viewer pushed on the ROOT navigator (was inside the bottom-nav shell).
- Bottom nav: no tab highlighted on non-tab screens (Home was lit on Profile etc.).
- Activity CTA: hidden when there is no valid internal route (was a dead button);
  no crash on non-string route.
- Privacy export: `exit_requests` filtered by `user_id` (column is not investor_id).
- KYC "Submitted on": falls back to `onboarded_at`.
- `read_at` written in UTC.
- OTP generic error no longer prints the raw exception.

## Not changed (needs a decision / live schema)
See the audit report in the Claude project (decisions-and-changes-d86).

## Round 2 (owner decisions, same day)
- Crops are not shown anywhere in the investor app: removed crop chips (My
  Projects, Explore tiles), the CROP card on Explore detail, and the Crops card
  on View Area. `Project.cropType` still carries `projects.tier` for the tier badge.
  Explore detail no longer invents a subscription deadline ("Dec 31, 2026");
  shows "To be announced" when unset.
- PIN lockout persisted in secure storage (AppLockService.recordPinFailure):
  3 wrong -> 30 s, 6 -> 5 min, 9 -> 30 min, 10 -> signed out (email code needed).
  Survives app kill/relaunch. Biometric or correct PIN resets the counter.
- ARL_AUTH_GATE_SECRET removed from the app and CI. It was compiled into the
  public web JS, and the repo copy of request-auth-email never checked it.
  VERIFY the deployed function doesn't require `x-arl-cron-secret` before
  shipping, or OTP requests will fail.
- CI: Flutter 3.24.x -> 3.41.x (matches pubspec.lock), dropped the removed
  `--web-renderer html` flag (web now uses CanvasKit), added
  `--no-web-resources-cdn` so CanvasKit is served from our own domain (the
  CSP would block gstatic). netlify.toml connect-src += fonts.gstatic.com
  (CanvasKit font fallback). Verified: build boots under the production CSP
  with zero violations.
- Gate check (app_config) now times out after 6 s so a slow network can't
  hold users on the splash.

## Round 3 — live schema + Jev field mapping
- `supabase/migrations/20260926000000_070_live_schema_baseline.sql`: live public
  schema extracted read-only from the dashboard (32 tables/views, 23 functions,
  22 triggers, 93 policies, grants, buckets, cron). Replayed on a Postgres 16
  replica with Supabase stubs: counts match live. Secrets excluded. Mark as
  applied on prod with `supabase migration repair --status applied 20260926000000`.
- `..._071_security_and_trigger_fixes.sql` (NOT APPLIED — owner to run):
  stage trigger `NEW.is_demo` bug (every stage advance errored), portfolio_summary
  RLS bypass (all investors' totals readable), anon-callable
  upsert_phase_project_update, blanket grants. Reproduced + verified on replica.
- Jev (TypeSafe jev-1.13.0) checked 158 field reads vs the live schema
  (tools/jev_field_map/REPORT.md). Fixed: KYC date -> kyc_submitted_at,
  contract start no longer from updated_at, no invented next-payout date,
  selector no longer shows project ticket size as the investor's investment,
  phantom crop_type removed.

## Round 4 — Zoho sync restored + alerting
- Zoho sync restored 2026-09-26 14:04 IST (new Self Client under Tech Team, scope
  ZohoCRM.modules.ALL; owner set the 3 ZOHO_* secrets). Reconcile, gallery and
  documents sync all ran clean.
- Soft-deleted the test allocation TEST-SAHIL-EKA-20260822 (investor_units
  66104f77..., deleted_at set; restorable by setting deleted_at = null). Active
  units now 2 = Zoho's 2 allocations.
- sync-stale-alert v9 written (NOT deployed - production deploy is the owner's):
  alerts on failed/missing sync RUNS (webhook_log) instead of data age, one
  alert + one email (Resend -> ARL_OPS_EMAIL) per job per 24h. v8 kept as
  index.v8.backup.ts.txt for rollback. After deploying, unschedule
  health-check-daily (calls an undeployed function, 404 daily).
