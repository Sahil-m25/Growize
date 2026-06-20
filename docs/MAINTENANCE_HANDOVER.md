# Growize / ARL Investor Portal — Maintenance Handover

**For:** the engineer taking over maintenance of this app.
**Written:** 2026-06-11. **Verify against the live system if anything looks off.**

This document is the single starting point for a new maintainer. It tells you
what the system is, where everything lives, how to run and ship it, what the
secrets and accounts are, how to keep it healthy, and which other documents to
read for depth. It is intentionally a map, not a full reference — the deep docs
it points to are the source of truth for each area.

---

## 1. What this app is

Growize is a **read-heavy investor portal** for ARL (AgResearch Labs) agri
investors. Investors sign in to see their portfolio: projects (farm LLPs) they
hold units in, capital and payouts, documents, a project marketplace, support
tickets, and account/KYC management.

- **Frontend:** Flutter (mobile + web). Currently shipping web at
  `growizefarm.com`; Android APK is sideloaded; iOS is planned (blocked on
  Apple Developer enrollment).
- **Backend:** Supabase (Postgres + Auth + Storage + Edge Functions).
- **Source of truth for investor data:** **Zoho CRM**. Supabase is a
  read-optimised mirror kept in sync by a real-time webhook plus a daily
  reconcile cron. **The app never writes investor/project/allocation data
  directly** — it reads from Supabase; mutations happen in Zoho and sync down.
- **No realtime UI** by design (data refreshes on screen/tab visits).

The golden rule that drives most of the architecture: **Zoho is upstream, the
app is downstream.** If you ever find yourself "fixing" investor data in
Supabase Studio, stop — the next sync will overwrite it. Fix it in Zoho.

---

## 2. Accounts and external services you need access to

Get access to each of these on day one (ask ARL Tech, `tech@agresearchlabs.com`):

| Service | What it's for | Where |
|---|---|---|
| **Supabase** project `oynfhdqizebvgmaoiuax` | DB, Auth, Storage, Edge Functions, logs, secrets | https://supabase.com/dashboard/project/oynfhdqizebvgmaoiuax |
| **Zoho CRM** (IN data centre) | Source of truth for investors/LLPs/allocations; Deluge sync functions + workflow rules | https://crm.zoho.in/ |
| **GitHub** (this repo) | Code, CI/CD workflows | repo host |
| **Netlify** | Web hosting / deploy target for `growizefarm.com` | Netlify dashboard |
| **Sentry** | Crash/error reporting (app + edge functions) | Sentry dashboard |
| **Resend** | Transactional email (ticket/ops notifications) | Resend dashboard |
| **Slack** | Consultation-request notifications (incoming webhook) | Slack workspace |
| **Apple Developer** | iOS build/signing (enrollment pending) | — |

---

## 3. Tech stack and key dependencies

Flutter 3.10+ / Dart 3.0+ (CI builds on the 3.24.x channel; Flutter is installed
locally at `C:\flutter\`). Notable packages (see `pubspec.yaml` for exact
versions):

- **flutter_riverpod** — state management (all app state is providers).
- **go_router** — navigation + deep links + route guards.
- **supabase_flutter** — auth, Postgres (PostgREST), storage.
- **hive / hive_flutter** — offline cache.
- **local_auth + flutter_secure_storage** — biometric/PIN app-lock.
- **sentry_flutter** — crash reporting (PII-scrubbed before send).
- **syncfusion_flutter_pdfviewer / pdfx** — document viewing.
- **screen_protector** — screenshot blocking on the documents screen.
- **share_plus, url_launcher, cached_network_image, connectivity_plus,
  package_info_plus, intl, crypto** — supporting libs.
- **Inter** font bundled in `assets/fonts/`.

---

## 4. Repository layout

```
lib/
├── main.dart              # startup: dotenv, Hive, Supabase init, Sentry, app-lock, gate check
├── app.dart               # thin app shell
├── core/
│   ├── theme/             # colours/tokens (match Growize App Design.html), text styles
│   ├── navigation/        # GoRouter routes, route_names, web URL strategy, auth redirect
│   ├── supabase/          # ArlSupabase client init + StorageHelper (signed URLs)
│   ├── auth/              # SessionManager (OTP sign-in), AppLock (PIN/biometric)
│   ├── repositories/      # data access per domain (investor, projects, financials, documents, ...)
│   ├── providers/         # Riverpod provider wiring
│   ├── offline/           # Hive cache, resilient cache, sync state
│   ├── observability/     # Sentry config + PII scrubber
│   ├── constants/         # Supabase URL/keys, support contacts, app links
│   ├── version/           # in-app version check + banner
│   └── widgets/           # MainScaffold, app bar, demo/lock banners, error view
└── features/              # one folder per feature, each with screens + widgets/ + providers
    ├── auth/        home/        projects/     financials/
    ├── documents/   gallery/     activity/     explore/
    ├── profile/     support/     exit/         onboarding/
    ├── gating/      celebration/ legal/

supabase/
├── config.toml            # project ref, per-function verify_jwt, auth/redirect/storage config
├── functions/             # edge functions (see §7) + _shared/ (cors, email, masking, supabase)
├── migrations/            # live migrations (058+; 001–057 squashed into migrations_archive_*)
└── README.md, setup.ps1/.sh

docs/                       # all operational + reference docs (see §10)
.claude/                    # decisions/, iterations/, status.md, INDEX.md — the change log
```

The Flutter **design source of truth** is `Growize App Design.html` at the repo
root (a single-file Tailwind prototype). The app is meant to match it; don't
invent new layouts (see `CLAUDE.md`).

---

## 5. Local development

```
# 1. Config
cp .env.example .env            # fill SUPABASE_URL + SUPABASE_ANON_KEY (and Sentry vars if testing)

# 2. Dependencies
& C:\flutter\bin\flutter.bat pub get

# 3. Static analysis (do this before every commit)
& C:\flutter\bin\dart.bat analyze lib

# 4. Run
& C:\flutter\bin\flutter.bat run -d chrome           # web
& C:\flutter\bin\flutter.bat run -d <android-device> # android
```

PowerShell is the preferred shell on Windows. If both Supabase URL and anon key
are empty, the app runs in **demo mode** with mock data — useful for pure-UI
work without a backend.

**Config injection.** The app reads config from compile-time `--dart-define`
first, then a bundled `.env` (native/dev only — web/Netlify skip dotfiles),
then falls back to demo mode. Release/CI builds pass
`--dart-define-from-file=.env.production`. The keys live in
`lib/core/constants/` — start there if you need to know what's being read.

---

## 6. Architecture and data flow (the part to understand first)

```
Zoho CRM (source of truth)
  Contacts · LLP_Creation_Module · LLP_UnitAllocation_Module
      │
      ├─ real-time: Zoho workflow rule → Deluge Push_*_To_Supabase
      │             → POST /functions/v1/zoho-crm-webhook  (X-ARL-Webhook-Secret)   ~seconds
      │
      └─ daily safety net: cron → /functions/v1/zoho-reconcile-daily               01:00 UTC
                         (re-pulls all modules, same handlers, idempotent)
      │
      ▼
   Postgres (RLS per auth.uid)  investors · llps · projects · investor_units · payouts · notifications · webhook_log
      │
      ▼
   PostgREST  (JWT + RLS)
      │
      ▼
   Flutter app  (read-only; Riverpod providers; Hive offline cache)
```

Key invariants:
- **Webhook (push) and reconcile (pull) converge on the same handlers** and are
  idempotent via unique keys (`webhook_log.idempotency_key`,
  `payouts.idempotency_key`). Re-firing an event is safe.
- **RLS everywhere.** Every investor-facing table filters on `auth.uid()`.
  Edge functions use the service role (bypasses RLS); the app uses the
  authenticated role.
- **One Zoho LLP record fans out** to both `llps` (legal) and `projects`
  (operational), defaulting to `project.id == llp.id`. Each allocation's 10
  UTR/amount/date slots fan out into `payouts` rows.

Full reference: **`docs/data_flow_guide.md`** (read this once, end to end).

---

## 7. Edge functions (Deno, in `supabase/functions/`)

| Function | Trigger / auth | Purpose |
|---|---|---|
| `zoho-crm-webhook` | Zoho workflow, `X-ARL-Webhook-Secret` | Real-time upsert of contacts/LLPs/allocations. |
| `zoho-reconcile-daily` | cron 01:00 UTC, `CRON_SECRET` | Daily full re-pull; safety net for missed webhooks. |
| `onboard-investor` | `X-ARL-Admin-Secret` + JWT | Create the auth user + `investors` row for a new investor. |
| `gallery-sync` | cron ~06:00 IST, `CRON_SECRET` | Pull Zoho image attachments into `arl-gallery`. |
| `documents-sync` | cron ~06:15 IST, `CRON_SECRET` | Pull Zoho non-image attachments into `arl-documents` (project + personal). |
| `create-ticket` / `reply-ticket` | investor JWT | Support tickets (rate-limited); replies feed notifications. |
| `bank-change-request` | investor JWT | Investor-requested bank change → `bank_change_requests` (human-approved). |
| `request-auth-email` | public | Sends the email OTP for sign-in; generic response (no user enumeration). |
| `latest-app-version` | public | Returns newest APK release for the in-app update banner. |
| `sync-stale-alert` | cron hourly, `CRON_SECRET` | Flags stale tables into `sync_alerts`. |
| `health-check` | cron daily, `CRON_SECRET` | Emails ops a summary of webhook failures, cron failures, staleness. |
| `notify-consultation-request` | DB trigger | Posts new consultation requests to Slack. |

`verify_jwt` per function is set in `supabase/config.toml`. Cron/Zoho functions
use shared secrets (no JWT); investor-facing functions verify JWT.

Deploy a function: `supabase functions deploy <name>` (or via the setup
scripts). Each function has its own `README.md`.

---

## 8. Build and deploy

### Web (growizefarm.com / Netlify)

CI is a GitHub Actions workflow under `.github/workflows/` that, on push to
`main`, runs `flutter pub get` → writes `.env.production` from repo secrets →
`flutter build web --release --dart-define-from-file=.env.production` → deploys
the `build/web/` output to Netlify. `netlify.toml` defines the SPA catch-all,
static `/terms` + `/privacy` pages, security headers (CSP allows Supabase,
Sentry, Google Fonts), and cache rules. Confirm the exact workflow filename and
flags in the repo before relying on them.

Manual web build (Windows): run `build_web.ps1`, then drag `build/web/` to
Netlify drop if needed.

### Android (sideloaded APK)

```
& C:\flutter\bin\flutter.bat build apk --release --dart-define-from-file=.env.production
```

Signing uses `android/app/release-keystore.jks` + `android/key.properties`
(git-ignored). **The committed keystore ships with a placeholder password — a
real release keystore and password must be set before public distribution**
(`docs/ops/keystore_setup.md`). App id `com.arl.app`; min SDK 23 (required for
biometrics).

Cutting a release (so the in-app banner offers the update):
1. Bump `version: X.Y.Z+N` in `pubspec.yaml` (N is the version_code).
2. Build the APK.
3. Upload it to the `app-releases` Supabase storage bucket (public).
4. Insert a row into the `app_releases` table (version_code, version_name,
   apk_url, release_notes, is_critical). See `docs/ops/version_check_setup.md`.

### iOS

Not yet shipped — blocked on Apple Developer enrollment. No signing config in
the repo today.

---

## 9. Secrets, monitoring, and routine maintenance

### Where secrets live
- **Edge function secrets** (e.g. `WEBHOOK_SECRET`, `ADMIN_SECRET`, `ZOHO_*`,
  `RESEND_API_KEY`, `SENTRY_EDGE_DSN`, `SLACK_CONSULTATION_WEBHOOK_URL`):
  Supabase Dashboard → Edge Functions → Secrets (`supabase secrets set ...`).
- **Cron secret** (`CRON_SECRET`): Postgres Vault — pg_cron jobs read it and
  pass it as the `x-arl-cron-secret` header.
- **App config** (`SUPABASE_URL`, `SUPABASE_ANON_KEY`, Sentry vars): injected at
  build time via `.env.production` (CI secrets). Anon key is public by design;
  the service role key is never shipped to clients.
- **Never commit** real secrets. `.env` is git-ignored; `.env.example` is the
  template.

### Monitoring / health
- **Sentry** for crashes (app + edge). PII is scrubbed in `core/observability/`.
- **`health-check`** edge function emails ops a daily summary (webhook
  failures, cron failures, staleness).
- **`sync-stale-alert`** populates `sync_alerts` hourly.
- **`webhook_log`** is your first stop when sync looks wrong:
  `SELECT received_at, status, event_type, error_message FROM webhook_log WHERE status='failed' ORDER BY received_at DESC LIMIT 20;`

### Routine / common tasks
- **Investor data looks stale:** check `webhook_log`, then force-fire
  `zoho-reconcile-daily` or the relevant Deluge `Push_*` function — see
  `docs/ops_admin_guide.md` Recipe 4.
- **App-wide gate / maintenance mode / force-update:** `app_config` table rows
  (`maintenance_mode`, `min_app_version`, ...) — Recipe 5 in the ops guide.
- **Most day-to-day ops** (onboarding, allocations, payouts, documents,
  bank-change, exit/consultation triage, DPDP erasure requests): all in
  `docs/ops_admin_guide.md`. There is **no admin UI yet** — ops is Supabase
  Studio + Zoho.
- **Engineer debugging playbook:** `docs/debug_runbook.md`.

### Database changes
Migrations live in `supabase/migrations/` and are applied with the Supabase
CLI / MCP. **Migrations 001–057 were squashed into `migrations_archive_*` on
2026-06-08; live migrations now start at 058.** Current high-water mark is **062**.
Don't change the `portfolio_summary` view's `security_invoker` setting — it
enforces RLS on PII. Log schema decisions under `.claude/decisions/` and update
`.claude/INDEX.md` (project convention).

---

## 10. Where everything is documented (read map)

| Need | Read |
|---|---|
| How the app works for ops / how to edit investor data safely | `docs/ops_admin_guide.md` (canonical; **Part 11 = current state**) |
| Architecture, sync paths, every field's lineage | `docs/data_flow_guide.md` |
| Engineer failure playbook ("it broke at 2am") | `docs/debug_runbook.md` |
| Topic deep-dives (tickets, marketplace, documents, investor profile) | `docs/ops/*.md` |
| Android signing | `docs/ops/keystore_setup.md` |
| Cutting an app release / version check | `docs/ops/version_check_setup.md` |
| Monitoring & alerts | `docs/ops/monitoring_alerts.md` |
| v1.1 plans (admin panel, in-app PDF viewer, etc.) | `docs/ops/v1.1_roadmap.md`, `docs/plans/2026-05-20_admin_panel_and_pdf_viewer_spec.md` |
| QA / verification | `docs/testing/TEST_PLAN.md`, `docs/testing/SCENARIOS.md`, `docs/ARL_Growize_Smoke_Test_Checklist.md` |
| Latest E2E verdict + defects | `docs/e2e_test_results_full_v31_2026-05-16.md` |
| Page-by-page parity audit | `docs/audit_pagebypage_2026-05-20.md` |
| Project conventions & build commands | `CLAUDE.md` |
| Every design/implementation decision, chronological | `.claude/decisions/` + `.claude/INDEX.md` |
| Current phase / latest status | `.claude/status.md` |

---

## 11. Known gaps and tech debt to be aware of

- **No admin UI.** All ops happens in Supabase Studio + Zoho. An admin panel is
  specced (Retool, ~3–4 weeks) but not built.
- **In-app PDF viewer** is specced for v1.1.
- **Soft-deletes from Zoho** are partially handled; deleted CRM records can
  linger in Supabase. See the defect roll-up in `docs/ops_admin_guide.md` Part 10.
- **Custom SMTP not configured** — auth email rides Supabase's default backend,
  which limits invite quota and reliability. **The OTP login depends on the
  Supabase "Magic Link" email template rendering `{{ .Token }}`** (see ops guide
  §11.1) — if that template is reset, logins break.
- **Field-list alignment risk:** the field lists in `zoho-reconcile-daily` must
  match the Deluge `Push_*` functions, or reconcile can overwrite good CRM
  values with blanks. Treat any new Zoho field as a two-sided change.
- **CORS allow-list re-deploy** and a couple of data fixes (e.g. a NULL-priced
  allocation) are open at launch — see `docs/e2e_test_results_full_v31_2026-05-16.md`.

---

## 12. First-week checklist

1. Get access to every service in §2.
2. Read `docs/data_flow_guide.md` and `docs/ops_admin_guide.md` (at least Parts
   1–4 and Part 11).
3. Run the app locally against the real backend (`flutter run -d chrome`).
4. Skim `.claude/INDEX.md` to see the decision history; read the most recent
   5–10 decisions.
5. Watch one webhook fire end to end: edit a `-demo` Contact in Zoho, then watch
   `webhook_log` and the `investors` row update.
6. Do a dry-run web build locally; review the GitHub Actions workflow so you
   know how a real deploy happens before you trigger one.
7. Confirm you can read Sentry and the `health-check` email.

When in doubt: Zoho is upstream, Supabase mirrors it, the app reads it. Don't
write investor data into Supabase by hand.
