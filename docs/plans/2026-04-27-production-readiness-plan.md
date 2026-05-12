# Growize Production Readiness Plan

**Generated**: 2026-04-27 after Day 1 backend lockdown
**Target launch**: 2026-05-05 (8 days)
**Status**: 4× 🔴 backend issues closed today; ~7 days of remaining work organized below for parallel execution.

---

## 0. Read me first

This document is the single source of truth for everything still required to ship Growize on May 5. It's organized into **8 work streams** that you can run in parallel using multiple Claude agents. Each task has:

- **Scope** — one sentence of what gets done
- **Files** — exact paths the work touches
- **Implementation** — the key code changes / SQL / migrations
- **Verification** — read-only probes you can run to confirm it worked
- **🔓 Attack tests** — how to actively try to break the fix and confirm it holds

The attack tests aren't optional. For a financial portal, "I think it works" is not the same as "I tried to break it and couldn't." Every 🔴 / 🟠 fix in this document includes an adversarial check.

**Conventions:**
- Task IDs are `S.Tn` where `S` is the stream letter (A–H) and `n` is the task number.
- `PARALLEL-OK` means the task can run alongside others.
- `DEPENDS ON: S.Tn` means another task must finish first.
- All SQL probes assume the Supabase MCP `execute_sql` tool. CLI alternatives are `psql $DATABASE_URL` or the Supabase Studio SQL editor.

---

## 1. Current state (what shipped today)

| Fix | Live state |
|---|---|
| `portfolio_summary` view leak (🔴 #1) | Closed — `security_invoker = on`. Verified live. |
| `gallery-sync` publicly invokable (🔴 #7) | Closed — `x-arl-cron-secret` header check. Vault-stored secret. |
| Edge-Function-only writes (🔴 #2) | Closed — INSERT policies dropped on `support_tickets`, `ticket_messages`, `bank_change_requests`. |
| Migration drift (🔴 #11) | Closed — 17 migrations materialised in `supabase/migrations/`. |
| Zoho payload PII leak (🟠 #8 → 🔴 due to May 5 cutover) | Closed — `webhook_log.payload` pre-masked. |
| Edge function repo↔deployed drift | All 6 functions redeployed; repo files match deployed 1:1. |
| Quality polish across all 6 functions | Constant-time secret compare, escapeHtml, proper CORS preflight, length caps. |

**Action you still owe (one-time, ~30 seconds):**

```bash
supabase secrets set CRON_SECRET=362f7679765695d690b28a9c93bae93ed0d70f0299bd27e51180c4b072ac51ba \
  --project-ref oynfhdqizebvgmaoiuax
```

Without this, tomorrow's `gallery-sync` cron returns 401 and skips. Set it before 00:30 UTC tomorrow.

---

## 2. Required prerequisites (do BEFORE starting any stream)

### 2.1 Set the CRON_SECRET (above) — non-negotiable

### 2.2 Confirm secrets that should already be set

Run from the project root:
```bash
supabase secrets list --project-ref oynfhdqizebvgmaoiuax
```

Expected env vars (set, but values not shown):

| Secret | Used by | Required |
|---|---|---|
| `SUPABASE_URL` | every edge fn | yes (auto-set) |
| `SUPABASE_SERVICE_ROLE_KEY` | every edge fn | yes (auto-set) |
| `SUPABASE_ANON_KEY` | every edge fn | yes (auto-set) |
| `ADMIN_SECRET` | onboard-investor | yes |
| `WEBHOOK_SECRET` | zoho-crm-webhook | yes |
| `CRON_SECRET` | gallery-sync | **yes — set today** |
| `RESEND_API_KEY` | create-ticket / reply-ticket / bank-change-request | yes (otherwise emails silently skip) |
| `ARL_OPS_EMAIL` | same three | optional, defaults to `ops@agresearchlabs.com` |
| `ZOHO_CLIENT_ID` / `ZOHO_CLIENT_SECRET` / `ZOHO_REFRESH_TOKEN` | gallery-sync | yes (otherwise gallery sync silently no-ops) |

**If any of `ADMIN_SECRET`, `WEBHOOK_SECRET`, or `RESEND_API_KEY` is missing**, set it now. Without `WEBHOOK_SECRET`, the moment Zoho fires its first real webhook it returns 401 and you lose the event silently.

### 2.3 Plan upgrade

- Upgrade project `oynfhdqizebvgmaoiuax` to **Pro plan**.
- Add **PITR** (point-in-time recovery) add-on (~$100/mo).
- Verify in Dashboard → Project Settings → Database → Backups that PITR shows ≥7 day window.

PITR is the safety net for every DDL change in Streams C and E. Without it, you have only nightly snapshots.

### 2.4 Have ready

- A test email address you control (for the test investor).
- A test phone number you control (for OTP if you go that route).
- Sentry account with a project for "Growize Flutter" and one for "Growize Edge Functions" (free tier is fine).
- A real Android device for the smoke walk in Stream H.

---

## 3. The 8 streams (overview + dependency graph)

```
            ┌──────────────────────────────────────┐
            │  Wave 1 — fully parallel             │
            ├──────────────────────────────────────┤
            │  Stream A  Flutter feature wiring    │
            │  Stream C  Backend RLS/perm cleanup  │
            │  Stream G  Red-team test suite       │
            └──────────────────────────────────────┘
                                ↓
            ┌──────────────────────────────────────┐
            │  Wave 2 — parallel after Wave 1      │
            ├──────────────────────────────────────┤
            │  Stream B  Flutter hardening         │
            │  Stream D  Performance polish        │
            │  Stream E  Observability             │
            │  Stream F  Demo persona              │
            └──────────────────────────────────────┘
                                ↓
            ┌──────────────────────────────────────┐
            │  Wave 3 — sequential                 │
            ├──────────────────────────────────────┤
            │  Stream G  Run attack suite          │
            │  Stream H  Smoke walk + cutover      │
            └──────────────────────────────────────┘
```

Stream sizes (rough wall-clock with one agent each):

| Stream | Size | Touches |
|---|---|---|
| A. Flutter feature wiring | 1.5 – 2 days | 2 specific Flutter screens + repo wiring |
| B. Flutter hardening | 1 day | dotenv, router, session, storage helpers |
| C. Backend RLS/perm cleanup | 0.5 day | 3–4 migrations |
| D. Performance polish | 0.5 day | repositories, providers, signed URLs |
| E. Observability | 1 day | Sentry, health-check edge function, cron |
| F. Demo persona | 1 day | demo_data.dart, mode flags |
| G. Red-team test suite | 0.5 day to write, 0.5 day to run | shell scripts, no app code |
| H. Cutover prep + smoke | 0.5 day | runbook, real device |

With 2 parallel agents, total wall-clock ≈ 4 days. With 3 agents, ≈ 3 days.

---

## 4. Stream A — Flutter feature wiring

**PARALLEL-OK with C and G.**
**TOUCHES**: `lib/features/profile/bank_details_screen.dart`, `lib/features/support/ticket_detail_screen.dart`, `lib/core/repositories/support_repository.dart` (small additions)
**SIZE**: 1.5 – 2 days

### A.T1 — Wire `BankDetailsScreen` to real data + Edge Function

**Scope.** Replace the hardcoded "Sahil Kumar / HDFC ****5678" mockup with the real signed-in investor's bank fields, and wire the "Request Change" button to the `bank-change-request` Edge Function with a proper form modal.

**Files.**
- `lib/features/profile/bank_details_screen.dart` — replace top-to-bottom
- `lib/core/providers/repositories.dart` — exposes `currentInvestorProvider` (already exists, no change)

**Implementation.**
- Convert to `ConsumerWidget`. Watch `currentInvestorProvider`.
- Display fields from the investor row: `bank_name`, `bank_account_masked`, `bank_ifsc`, `bank_holder_name`. Show a kyc/verified pill if `kyc_status == 'verified'`.
- "Request Change" opens a modal/bottom sheet with 4 fields: bank name, account number (masked input — show last 4 only after typing 5+ chars), IFSC, account holder name.
- On submit, mask the account number client-side to `XXXX-XXXX-{last4}` (same pattern as `bank-change-request` validates), then call `ref.read(supportRepositoryProvider).requestBankChange(...)`.
- Surface errors: `429 rate_limited` → "You already have a pending request" with `existing_request_id`. `400 invalid mask` → "Account number invalid." Other errors → friendly fallback.
- After success, show a toast and refresh `currentInvestorProvider` (the row won't change until ops approves, but a "Pending" pill should appear if any `bank_change_requests` row is pending — query that too).
- Show a "Pending request" card if `myBankChangeRequests()` returns at least one `status='pending'` row.

**Verification.**
- Build and install. Sign in as the test investor. Bank Details screen shows the actual investor's masked account, not "Sahil Kumar".
- Tap Request Change, fill form, submit. Confirm a `bank_change_requests` row exists in Supabase Studio and ops received an email.
- Submit a second request immediately. Confirm 429 is shown to user.
- Wait 7 days OR manually delete the pending row. Submit again. Confirm success.

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| Pass raw account number (`123456789012`) instead of masked | Edge Function returns `400 account_masked must already be masked`. |
| Tamper with `investor_id` in the request body to another investor's UUID | `investor_id` is set server-side from the JWT. Row is created against the *caller*, never the victim. Verify in DB. |
| Spam Request Change 10 times in a loop while the first is pending | First succeeds; rest get 429. |
| Pass `<script>alert(1)</script>` in `bank_name` | Ops email shows the literal text (escapeHtml), not an executable script. View the rendered email in Resend dashboard or the inbox source. |
| Replay the request after ops approves | A new pending row is created (allowed — old one is `approved` so cooldown doesn't trigger). Confirm this is the intended behavior. |

**Agent prompt template** (for a fresh Claude agent):
```
I'm wiring up the BankDetailsScreen for the Growize Flutter app. The screen
currently shows hardcoded mock data (lib/features/profile/bank_details_screen.dart
shows "Sahil Kumar / HDFC ****5678" to every user) and the "Request Change"
button only displays a SnackBar.

Replace it with a ConsumerWidget that:
1. Reads the signed-in investor's bank fields via currentInvestorProvider
   (in lib/core/providers/repositories.dart). Show bank_name,
   bank_account_masked, bank_ifsc, bank_holder_name. Show a "Verified" pill
   when kyc_status == 'verified'.
2. Adds a "Pending" pill when supportRepository.myBankChangeRequests()
   contains at least one row with status='pending'.
3. Opens a modal bottom sheet on "Request Change" with 4 fields. Validate
   account number input — accept either raw digits OR an already-masked
   format. Mask client-side to "XXXX-XXXX-{last4}" before calling
   supportRepository.requestBankChange().
4. Surfaces these errors to the user via SnackBar with friendly text:
   429 rate_limited → "You already have a pending request"
   400 with "must already be masked" → "Invalid account number"
   any other error → "Could not submit — try again"
5. Refreshes currentInvestorProvider on success.

Keep the visual style consistent with the rest of the app (ArlColors,
ArlRadii, the cream background). The reference for design is the existing
KYC and Profile screens.

After implementing, build the Flutter app (flutter analyze + flutter build
apk --debug at minimum) and report any errors. Do not modify the Edge
Function — it's already deployed and working.
```

### A.T2 — Wire `TicketDetailScreen` to real data + reply-ticket

**Scope.** Replace the hardcoded fake ticket conversation with real ticket + messages from Supabase, and add a reply input wired to `reply-ticket`.

**Files.**
- `lib/features/support/ticket_detail_screen.dart` — replace
- `lib/features/support/ticket_provider.dart` — **NEW** file with the providers
- `lib/core/repositories/support_repository.dart` — already has `ticketById()` and `messagesFor()`

**Implementation.**
- Convert to `ConsumerStatefulWidget` (need a `TextEditingController` for the reply input).
- Two new providers in `ticket_provider.dart`:
  ```dart
  final ticketByIdProvider = FutureProvider.family<Map<String,dynamic>?, String>((ref, id) async {
    return ref.read(supportRepositoryProvider).ticketById(id);
  });
  final ticketMessagesProvider = FutureProvider.family<List<Map<String,dynamic>>, String>((ref, id) async {
    return ref.read(supportRepositoryProvider).messagesFor(id);
  });
  ```
- The screen watches both. Header shows ticket subject, category badge, status pill.
- Body shows messages in chronological order; `sender_type='investor'` = right-aligned cream bubble; `sender_type='staff'` = left-aligned green bubble.
- Reply input + send button at the bottom. **Disabled** when ticket status == `'resolved'` (with a "This ticket is closed" placeholder).
- Send button calls `supportRepository.replyTicket(ticketId, body)`. On success, invalidate `ticketMessagesProvider(id)` so the new message appears.
- Surface errors: `400 ticket_resolved` → "This ticket is closed", `404 ticket not found` → "This ticket no longer exists" + bounce back, generic → "Could not send reply".

**Verification.**
- Sign in. Navigate to /ticket/{real_ticket_id}. Real conversation displayed.
- Type a reply, send. New bubble appears; row in `ticket_messages` table.
- Mark ticket as `resolved` in Studio. Refresh. Reply input disabled.

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| Navigate to /ticket/{another investor's ticket id} | RLS rejects the SELECT. UI shows "ticket not found" or empty state. Verify in Network tab — request returned 0 rows. |
| Modify the JWT to claim another user's id | `auth.getUser(token)` rejects (the JWT signature won't match). 401. |
| POST directly to `/rest/v1/ticket_messages` with valid JWT | RLS rejects (INSERT policy was dropped today). 401 / 42501. |
| Send a reply to a resolved ticket via Edge Function | 400 `ticket_resolved`. |
| Reply body contains 6000+ chars | 400 `body too long`. |
| Reply body contains `<img src=x onerror=alert(1)>` | Stored in DB literally. In ops email it's escapeHtml-ed. Verify in Resend dashboard. |

**Agent prompt template:**
```
I'm wiring up the TicketDetailScreen for the Growize Flutter app. Current
state: lib/features/support/ticket_detail_screen.dart shows a hardcoded
fake conversation about a "March payout" — completely ignores the
ticketId param. The reply-ticket Edge Function exists and works (deployed,
self-tested today).

Replace it with a ConsumerStatefulWidget that:
1. Loads the ticket via a new FutureProvider.family that calls
   supportRepository.ticketById(ticketId). Loads messages via another
   FutureProvider.family on supportRepository.messagesFor(ticketId).
2. Renders messages chronologically. sender_type='investor' = cream bubble
   right-aligned; sender_type='staff' = green bubble left-aligned.
3. Header: ticket subject, category badge, status pill (Open/In Progress/
   Resolved with appropriate colors).
4. Reply input + send button at the bottom. DISABLED when ticket.status ==
   'resolved' with a "This ticket is closed" placeholder.
5. Send calls supportRepository.replyTicket(ticketId, body). On success,
   invalidate the messages provider so the new message appears immediately.
6. Surface errors:
     400 ticket_resolved → "This ticket is closed"
     404 → "Ticket not found" + bounce back
     other → "Could not send reply"

Create lib/features/support/ticket_provider.dart with the providers.
Keep visual style consistent with the rest of the app.

After implementing, run flutter analyze and report any errors.
```

---

## 5. Stream B — Flutter hardening

**PARALLEL-OK with D, E, F. DEPENDS ON: nothing structural, but ideally after Stream A so screens exist.**
**TOUCHES**: `lib/main.dart`, `lib/core/supabase/supabase_client.dart`, `lib/core/auth/session_manager.dart`, `lib/core/navigation/router.dart`, `lib/features/auth/login_screen.dart`, `lib/core/supabase/storage_helper.dart`, several `*_provider.dart`
**SIZE**: 1 day

### B.T1 — Hard-fail dotenv in release builds

**Scope.** Today, `main.dart` swallows dotenv failures silently and the app drops into demo mode unauthenticated. In release builds, missing env config must be a hard crash, not a silent UX hole.

**Files.** `lib/main.dart`

**Implementation.**
```dart
import 'package:flutter/foundation.dart';

try {
  await dotenv.load(fileName: '.env');
} catch (e, st) {
  if (kReleaseMode) {
    // Crash visibly; nothing past here is safe in release.
    debugPrint('FATAL: .env failed to load in release: $e');
    rethrow;
  }
  // Debug/profile: tolerate so design previews still work.
  debugPrint('dotenv missing — continuing in demo mode (debug only)');
}
```

After load succeeds, also assert env contents:
```dart
if (kReleaseMode && (!SupabaseConstants.isConfigured || SupabaseConstants.devBypassAuth)) {
  throw StateError(
    'Release build refuses to start: env missing or ARL_DEV_BYPASS=true. '
    'Verify .env was bundled into the build.',
  );
}
```

**Verification.**
- `flutter build apk --release` then install. App launches normally.
- Edit `.env` to remove `SUPABASE_URL`. Rebuild release. App must crash on launch (not show demo content).

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| Build release with empty .env | App crashes on launch, no demo data shown. |
| Build release with `ARL_DEV_BYPASS=true` | App crashes on launch. |
| Build debug with empty .env | App starts in demo mode (intended for design preview). |

### B.T2 — Gate dev-bypass behind `kReleaseMode`

**Scope.** `LoginScreen._signInPassword` short-circuits to `/home` when `devBypassAuth || isDemoMode`. Combined with B.T1's silent failure path, a misconfigured prod could let anyone in. Move the bypass behind a hard release-mode gate.

**Files.** `lib/core/constants/supabase_constants.dart`, `lib/features/auth/login_screen.dart`

**Implementation.** In `supabase_constants.dart`:
```dart
static bool get devBypassAuth =>
    !kReleaseMode &&
    (dotenv.maybeGet('ARL_DEV_BYPASS', fallback: 'false') ?? 'false').toLowerCase() == 'true';
```
The `!kReleaseMode &&` clause means even if `ARL_DEV_BYPASS=true` ships in `.env`, release builds ignore it.

In `login_screen.dart` line 67: confirm the dev-bypass branch only runs when `devBypassAuth` is true. With the change above, in release this is unreachable.

**Verification.**
- Set `ARL_DEV_BYPASS=true` in `.env`. Build release. Try to log in with bogus credentials. Sign-in fails (expected — bypass is gated off). Build debug. Bogus credentials work.

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| Reverse-engineer the APK and look for `kReleaseMode` constant | Should be a baked-in `true` for release builds. The bypass branch is dead code. |
| Patch `.env` after install to set `ARL_DEV_BYPASS=true` | No effect — `kReleaseMode` is compile-time. |

### B.T3 — `GoRouterRefreshStream` for auth state

**Scope.** Today the router only re-runs `redirect()` on navigation. Background sign-out (token refresh failure, deleted user) doesn't redirect until the user manually navigates.

**Files.** `lib/core/navigation/router.dart`, `lib/core/auth/session_manager.dart`

**Implementation.** Add a refresh stream class (Flutter cookbook):
```dart
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _subscription;
  @override void dispose() { _subscription.cancel(); super.dispose(); }
}
```
Wire it into the router:
```dart
return GoRouter(
  initialLocation: RouteNames.home,
  refreshListenable: GoRouterRefreshStream(SessionManager.authStateChanges),
  redirect: ...,
  ...
);
```

**Verification.**
- Sign in. While on /home, run in Studio: `DELETE FROM auth.users WHERE id = '<test_uid>';`.
- Wait ~10 seconds (Supabase JS picks up the failure on next refresh). The app should auto-redirect to /auth.

**🔓 Attack test.** Sign in on Device A. Sign out on Device B (forces a refresh-token rotation). Device A's next refresh should fail; Device A redirects to /auth automatically.

### B.T4 — Forgot-password flow

**Scope.** Login has no recovery path today. Add a "Forgot password?" link → email reset flow.

**Files.** `lib/core/auth/session_manager.dart`, `lib/features/auth/login_screen.dart`, possibly a new `forgot_password_screen.dart`

**Implementation.** In `SessionManager`:
```dart
static Future<void> requestPasswordReset(String email) async {
  final client = ArlSupabase.requireClient();
  await client.auth.resetPasswordForEmail(
    email,
    redirectTo: 'com.arl.app://auth',
  );
}
```
Login screen: under the password field, a "Forgot password?" `TextButton`. Tapping opens a modal that asks for email, calls `requestPasswordReset`, shows "Check your inbox" toast.

The reset deep-link will land in /auth with a recovery token. Need a small handler that calls `client.auth.updateUser(password: newPassword)` after the user enters a new password.

**Verification.** Tap Forgot password, enter your test email, receive an email, click the link, app opens, type new password, sign in successfully with the new password.

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| Spam reset for a victim's email 100x | Supabase rate-limits at the auth level (default 4/hr). 429 after 4. |
| Reset for an email that doesn't exist | No error returned (Supabase returns 200 either way to prevent enumeration). Verify response is identical for valid + invalid emails. |
| Click an old recovery link after using a newer one | Old link's token is consumed/expired. App rejects gracefully. |

### B.T5 — `StorageHelper.clear()` on sign-out

**Scope.** The signed-URL cache is a process-global static map. After sign-out + sign-in-as-different-user, the new user briefly sees URLs from the previous user.

**Files.** `lib/core/supabase/storage_helper.dart`, `lib/core/auth/session_manager.dart` or `lib/main.dart`

**Implementation.** In `main.dart` after Supabase init:
```dart
ArlSupabase.client?.auth.onAuthStateChange.listen((event) {
  if (event.event == AuthChangeEvent.signedOut ||
      event.event == AuthChangeEvent.userDeleted) {
    StorageHelper.clear();
  }
});
```

**Verification.** Sign in as user A. Browse gallery (URLs cached). Sign out. Sign in as user B. Inspect URL cache; should be empty before B's first request.

**🔓 Attack test.** Sign in as A. Note a signed URL from the gallery (it's tied to A's project). Sign out. Sign in as B (different projects). Try to GET the noted URL — Supabase Storage rejects because the URL was issued to A's session-bound permission. Confirm 401/403.

### B.T6 — Demo fallthrough fix (5 providers)

**Scope.** Today, `notificationsProvider`, `documentsProvider`, `galleryProvider`, `payoutsProvider`, `projectPhasesProvider` all fall back to demo data when real data is empty. For an authenticated investor with no notifications, this shows fake data. Misleading.

**Files.** `lib/features/{activity,documents,gallery,financials,projects}/*_provider.dart`

**Implementation.** Pattern per provider:
```dart
final notificationsProvider = FutureProvider<List<ArlNotification>>((ref) async {
  final repo = ref.watch(activityRepositoryProvider);
  final investor = await ref.watch(currentInvestorProvider.future);
  if (investor != null) {
    // Authenticated — return real data, even if empty
    return repo.notifications();
  }
  // Unauthenticated demo browsing
  return demoNotifications();
});
```

For each consumer, add empty-state UI: "No notifications yet — you'll see updates here when ARL has news for you."

**Verification.** Sign in as the test investor (who has 0 notifications, 0 docs, 0 photos). All five screens show empty-state UI, NOT demo data. Sign out, browse same screens. Demo data appears.

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| Sign in. Inspect Network tab on each screen. | Only one query per screen, returning 0 rows. No fallback fetch to a demo source. |
| Patch the response to return null (DevTools / proxy) | Empty state, not demo data. |

### B.T7 — Wire `app_config` force-update + maintenance gate

**Scope.** `app_config` table has `min_app_version`, `latest_app_version`, `maintenance_mode` — but no Flutter code reads them.

**Files.** `lib/main.dart`, `lib/core/repositories/app_config_repository.dart`, **NEW** `lib/features/gating/force_update_screen.dart`, **NEW** `lib/features/gating/maintenance_screen.dart`

**Implementation.**
- On app startup (after Supabase init, before showing the home screen), call `appConfigRepository.all()`.
- Compare `min_app_version` to `pubspec.yaml`'s version (use `package_info_plus`).
- If current < min: show `ForceUpdateScreen` (full-screen blocker with "Update required — go to Play Store" + a deep link to `android_store_url`).
- If `maintenance_mode == 'true'`: show `MaintenanceScreen` with `maintenance_message`.
- Otherwise proceed normally.

```dart
final config = await ref.read(appConfigRepositoryProvider).all();
final minVersion = config['min_app_version'] ?? '1.0.0';
final maintenanceMode = config['maintenance_mode'] == 'true';
final maintenanceMessage = config['maintenance_message'] ?? '';
```

Add a `package_info_plus` dependency.

**Verification.**
- Set `app_config.min_app_version = '99.0.0'` in Studio. Reopen app. Force-update screen shown.
- Reset to `1.0.0`. Set `maintenance_mode = 'true'`. Reopen. Maintenance screen.
- Reset both. App opens normally.

**🔓 Attack test.** A malicious build that ignores `app_config` would have to be a custom-compiled APK. Since the gate is in client code, it's bypassable by sophisticated users. That's an inherent limitation; the gate is still useful for handling normal store rollout / outage windows. Document this expectation.

### Stream B agent prompt template

```
I'm hardening the Growize Flutter app for production launch. There's an
8-day deadline (May 5, 2026). Today is April 27. Apply seven specific
changes; treat each as independently testable.

Reference doc: docs/plans/2026-04-27-production-readiness-plan.md, Stream B.
Each task in there has Implementation + Verification + Attack tests
sections — follow them precisely.

Tasks (apply in this order — they don't conflict):
  B.T1 Hard-fail dotenv in release       (lib/main.dart)
  B.T2 Gate dev-bypass behind kReleaseMode (supabase_constants.dart, login_screen.dart)
  B.T3 GoRouterRefreshStream             (router.dart)
  B.T4 Forgot-password flow              (session_manager.dart, login_screen.dart)
  B.T5 StorageHelper.clear() on sign-out (main.dart, storage_helper.dart)
  B.T6 Demo fallthrough fix              (5 *_provider.dart files)
  B.T7 app_config force-update gate      (main.dart, NEW screens)

After each task: flutter analyze. After all 7: flutter build apk --debug
and report any analyzer warnings or build errors. Do NOT modify any Edge
Functions, migrations, or backend config.
```

---

## 6. Stream C — Backend RLS / permission cleanup

**PARALLEL-OK with A and G. DEPENDS ON: nothing.**
**TOUCHES**: 4 new migration files only. No edge function or Flutter changes.
**SIZE**: 0.5 day

### C.T1 — Migration `018_policies_to_authenticated_role`

**Scope.** Today every public policy targets role `{public}`. Per Supabase RLS perf docs (test6), specifying `TO authenticated` skips evaluation entirely for `anon`. Rewrite every policy to target `authenticated` (and `anon` only where intentional, currently just `app_config: public read`).

**Files.** **NEW** `supabase/migrations/<timestamp>_018_policies_to_authenticated_role.sql`

**Implementation.** Drop and recreate every policy with `TO authenticated`:

```sql
-- Pattern (repeat for every policy in migration 012):
DROP POLICY "investors: read own row" ON public.investors;
CREATE POLICY "investors: read own row" ON public.investors
  FOR SELECT TO authenticated USING (id = (SELECT auth.uid()));
-- ... etc for all 11 policies (excluding webhook_log deny + app_config public read which already specify role)
```

Generate the migration by listing current policies first:
```sql
SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
FROM pg_policies WHERE schemaname='public' ORDER BY tablename, policyname;
```

**Verification.**
```sql
-- After: all should show {authenticated}
SELECT tablename, policyname, roles FROM pg_policies
WHERE schemaname='public' AND policyname NOT LIKE '%public read%' AND policyname NOT LIKE '%deny%'
ORDER BY tablename;
```
Expect every row's `roles` to be `{authenticated}`.

**🔓 Attack tests.** All previous functional tests should still pass (sign in, see your data, can't see others'). Plus run an `EXPLAIN ANALYZE` on a hot query before and after — should see a plan-time improvement when called as anon (auth.uid() check skipped).

### C.T2 — Migration `019_revoke_default_grants`

**Scope.** Today, `anon`, `authenticated`, `service_role` all have `DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE` on every public table. RLS is the only protection. Defense-in-depth: REVOKE wide grants, leave only what RLS expects.

**Files.** **NEW** `supabase/migrations/<timestamp>_019_revoke_default_grants.sql`

**Implementation.**
```sql
-- Anon should only be able to read app_config (already covered by RLS).
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM anon;
GRANT SELECT ON public.app_config TO anon;

-- Authenticated needs:
--   SELECT on all public tables (RLS narrows what they see)
--   UPDATE on notifications.read_at only (covered by C.T3)
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;

-- service_role keeps everything (used by Edge Functions).
GRANT ALL ON ALL TABLES IN SCHEMA public TO service_role;

-- Sequences (gen_random_uuid handles PKs but USAGE on sequences may be
-- needed for any future serial column).
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO authenticated, service_role;
```

**Verification.**
```sql
SELECT grantee, table_name, string_agg(privilege_type, ',' ORDER BY privilege_type) AS privs
FROM information_schema.table_privileges
WHERE table_schema='public' AND grantee IN ('anon','authenticated','service_role')
GROUP BY grantee, table_name ORDER BY table_name, grantee;
```
Expect `anon` to have only `SELECT` on `app_config`; `authenticated` to have only `SELECT`; `service_role` to have everything.

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| Direct DELETE on `payouts` as authenticated | Permission denied (no DELETE grant). |
| Direct UPDATE on `investors.email` as authenticated | Permission denied (no UPDATE grant). |
| TRUNCATE `webhook_log` as anon | Permission denied (no TRUNCATE grant). |
| All Stream A flows (sign in, view data, file ticket via Edge Fn, view bank) | Still work — the SELECT grant is preserved and writes go via service-role. |

### C.T3 — Migration `020_notifications_column_grants`

**Scope.** Investors should be able to mark notifications as read, but not rewrite the title/body/metadata. Today the UPDATE policy permits any column.

**Files.** **NEW** `supabase/migrations/<timestamp>_020_notifications_column_grants.sql`

**Implementation.** Combine RLS + column-level grants:
```sql
-- Drop the broad UPDATE policy and re-create scoped to read_at only by
-- adding a check that no other column changed.
-- Simpler: use a column-level grant. Authenticated can UPDATE only read_at.
GRANT UPDATE (read_at) ON public.notifications TO authenticated;

-- The existing "notifications: mark own as read" policy still controls
-- which rows they can update; column grant controls which columns they
-- can write. Both must allow.
```

Note: Stream C.T2 already revoked all UPDATE; we re-grant just `read_at`.

**Verification.**
```sql
-- As authenticated, this should work:
UPDATE public.notifications SET read_at = NOW() WHERE id = '<own>';
-- As authenticated, this should fail:
UPDATE public.notifications SET title = 'pwned' WHERE id = '<own>';
```

**🔓 Attack tests.**

| Test | Expected |
|---|---|
| `UPDATE notifications SET title = 'X' WHERE id = '<own>'` as authenticated | Permission denied for column "title" of relation "notifications". |
| `UPDATE notifications SET read_at = NOW() WHERE id = '<own>'` | Succeeds. |
| `UPDATE notifications SET read_at = NOW() WHERE id = '<other_user>'` | RLS rejects (0 rows updated). |
| `UPDATE notifications SET investor_id = '<other_user>' WHERE id = '<own>'` | Permission denied for column "investor_id". |

### C.T4 — Migration `021_combine_projects_select_policies`

**Scope.** The advisor flagged "multiple permissive policies on `public.projects` for role `authenticated` for action `SELECT`." Combine the two into one.

**Files.** **NEW** `supabase/migrations/<timestamp>_021_combine_projects_select_policies.sql`

**Implementation.**
```sql
DROP POLICY "projects: marketplace listings visible to authenticated" ON public.projects;
DROP POLICY "projects: visible to investors with units" ON public.projects;

CREATE POLICY "projects: visible to investors with units OR marketplace"
  ON public.projects FOR SELECT TO authenticated
  USING (
    is_listed_in_marketplace = true
    OR id IN (
      SELECT project_id FROM public.investor_units
      WHERE investor_id = (SELECT auth.uid())
    )
  );
```

**Verification.** Re-run `mcp__55be8091-13df-4067-aa96-7d2cb54d2be9__get_advisors` — `multiple_permissive_policies` lint should clear.

### C.T5 — Dashboard: enable leaked-password protection

**Scope.** Advisor flagged auth → password settings → "Check passwords against HaveIBeenPwned" is off. Toggle it on.

**Manual step**: Dashboard → Authentication → Policies → Password → enable "Leaked password protection."

**Verification.** Re-run `get_advisors`. `auth_leaked_password_protection` lint should clear. Try to sign up with the password `Password123!` (known to be in HIBP); expect rejection.

### Stream C agent prompt template

```
Apply Stream C (backend RLS / permission cleanup) for the Growize Supabase
project (oynfhdqizebvgmaoiuax). Reference:
docs/plans/2026-04-27-production-readiness-plan.md, Stream C.

Apply 4 SQL migrations + flag 1 dashboard toggle:
  C.T1 Migration 018: rewrite public-role policies to TO authenticated
  C.T2 Migration 019: REVOKE default wide grants on public schema
  C.T3 Migration 020: column-level GRANT UPDATE(read_at) on notifications
  C.T4 Migration 021: combine projects SELECT policies
  C.T5 Note for user to enable leaked-password protection in dashboard

For each migration:
  1. Use the apply_migration tool (NOT execute_sql) so it's recorded.
  2. Write a matching file to supabase/migrations/<timestamp>_<name>.sql
     so the repo stays in sync.
  3. Run the verification query from the doc and report results.
  4. Run the listed attack tests via execute_sql with SET LOCAL ROLE
     authenticated and report whether they fail (correct) or succeed
     (broken).

Do NOT modify any Edge Functions or Flutter code. Pure DB work.
```

---

## 7. Stream D — Performance polish

**PARALLEL-OK with B, E, F. DEPENDS ON: nothing.**
**TOUCHES**: `lib/core/repositories/*.dart`, `lib/core/supabase/storage_helper.dart`, several `*_provider.dart`
**SIZE**: 0.5 day

### D.T1 — Batched signed URLs

**Scope.** Today `gallery_repository` and `documents_repository` create one signed URL per row in a parallel `Future.wait`. With 50 photos that's 50 storage RTTs.

**Files.** `lib/core/supabase/storage_helper.dart`, `lib/core/repositories/gallery_repository.dart`, `lib/core/repositories/documents_repository.dart`

**Implementation.** Add `signedUrlsForBucket(bucket, paths)` to `StorageHelper`:
```dart
static Future<Map<String, String>> signedUrlsForBucket(String bucket, List<String> paths) async {
  final client = ArlSupabase.client;
  if (client == null || paths.isEmpty) return {};
  // Filter out already-cached
  final fresh = paths.where((p) => _cache['$bucket::$p'] == null || _cache['$bucket::$p']!.expiresAt.isBefore(DateTime.now())).toList();
  if (fresh.isNotEmpty) {
    final results = await client.storage.from(bucket).createSignedUrls(fresh, _ttl.inSeconds);
    for (final r in results) {
      if (r.signedUrl != null) {
        _cache['$bucket::${r.path}'] = _Signed(r.signedUrl!, DateTime.now().add(_ttl));
      }
    }
  }
  return {for (final p in paths) p: _cache['$bucket::$p']?.url ?? ''};
}
```

In `gallery_repository`:
```dart
final paths = rows.map((r) => r['storage_path'] as String).toList();
final urls = await StorageHelper.signedUrlsForBucket(SupabaseConstants.galleryBucket, paths);
return rows.map((r) {
  final path = r['storage_path'] as String;
  return GalleryPhoto.fromSupabase(r, signedUrl: urls[path] ?? '');
}).toList();
```

**Verification.** Open Charles/Proxyman/Network tab. Load gallery with N>5 rows. Confirm one POST to `/storage/v1/object/sign/<bucket>` with all paths in the body, not N separate requests.

### D.T2 — `unreadCount` via `count: exact, head: true`

**Scope.** Today `unreadCount()` selects all unread IDs and counts in JS. Wasteful for chatty users.

**Files.** `lib/core/repositories/activity_repository.dart`

**Implementation.**
```dart
Future<int> unreadCount() async {
  final client = ArlSupabase.client;
  if (client == null) return 0;
  final res = await client
      .from('notifications')
      .select('id', const FetchOptions(count: CountOption.exact, head: true))
      .filter('read_at', 'is', null);
  return res.count ?? 0;
}
```

**Verification.** Inspect Network tab. Request body should be a `HEAD` (or have `Prefer: count=exact, head=true`). Response body should be empty; count comes from `Content-Range` header.

### D.T3 — Provider invalidation on auth state change

**Scope.** Today, signing out + signing in as a different user can briefly show the previous user's cached data in providers that don't depend on `currentInvestorProvider`.

**Files.** `lib/main.dart` (or a new `lib/core/auth/auth_invalidator.dart`)

**Implementation.**
```dart
ArlSupabase.client?.auth.onAuthStateChange.listen((event) {
  if (event.event == AuthChangeEvent.signedIn ||
      event.event == AuthChangeEvent.signedOut ||
      event.event == AuthChangeEvent.userUpdated ||
      event.event == AuthChangeEvent.userDeleted) {
    // Invalidate every cached provider that's user-scoped.
    final container = ProviderScope.containerOf(navigatorKey.currentContext!);
    container.invalidate(currentInvestorProvider);
    container.invalidate(portfolioSummaryProvider);
    container.invalidate(payoutsProvider);
    container.invalidate(projectsProvider);
    container.invalidate(notificationsProvider);
    container.invalidate(documentsProvider);
    container.invalidate(galleryProvider);
    StorageHelper.clear();
  }
});
```

(You'll need a top-level `navigatorKey` accessible to the listener. Or, simpler, expose a `Ref` via a top-level provider observer.)

**Verification.** Sign in as A, navigate to /gallery. Sign out, sign in as B. /gallery shows B's projects' photos, not a flash of A's.

### D.T4 — Trim `select()` columns

**Scope.** Repos use bare `.select()` which pulls every column. Trim to just what UI needs.

**Files.** Every repo. Suggested column lists:
- `currentInvestor()` → only what UI needs (`name, kyc_status, bank_*`, etc.)
- `myProjects()` → list view doesn't need GST/PAN/SPOC
- `marketplaceProjects()` → list view fields only

**Verification.** Inspect Network tab. Response payloads smaller.

### Stream D agent prompt

```
Apply Stream D (performance polish) for the Growize Flutter repo.
Reference: docs/plans/2026-04-27-production-readiness-plan.md, Stream D.

Tasks:
  D.T1 Batched signed URLs (storage_helper.dart, gallery + documents repos)
  D.T2 unreadCount via count: exact, head: true (activity_repository.dart)
  D.T3 Provider invalidation on auth state change (main.dart)
  D.T4 Trim select() columns to UI-needed fields

After each: flutter analyze. After all: flutter build apk --debug.
Do not change behavior — these are performance changes only.
```

---

## 8. Stream E — Observability

**PARALLEL-OK with B, D, F.**
**TOUCHES**: `lib/main.dart`, `pubspec.yaml`, **NEW** `supabase/functions/health-check/index.ts`, **NEW** migration
**SIZE**: 1 day

### E.T1 — Sentry on Flutter

**Scope.** Capture every Flutter exception (including the `.maybeSingle()` PostgrestException case from Phase 2 F1) with stack traces, user id, breadcrumbs.

**Files.** `pubspec.yaml`, `lib/main.dart`, `.env`

**Implementation.**
1. Add `sentry_flutter: ^8.0.0` to pubspec.
2. Create a Sentry project; copy DSN.
3. Add `SENTRY_DSN=<dsn>` to `.env`. Treat as non-secret (anon-equivalent).
4. In `main.dart`:
```dart
await SentryFlutter.init((options) {
  options.dsn = dotenv.maybeGet('SENTRY_DSN') ?? '';
  options.tracesSampleRate = 0.1;
  options.environment = kReleaseMode ? 'production' : 'debug';
}, appRunner: () => runApp(const ProviderScope(child: ArlApp())));
```
5. After auth state change, set the user:
```dart
Sentry.configureScope((scope) {
  scope.setUser(SentryUser(id: ArlSupabase.currentUserId));
});
```

**Verification.** Throw a synthetic exception in debug. See it in Sentry within ~1 minute.

### E.T2 — Sentry on Edge Functions

**Scope.** Capture every uncaught Edge Function exception with the function name, request ID, user (if known).

**Files.** `supabase/functions/{onboard-investor,zoho-crm-webhook,gallery-sync,create-ticket,reply-ticket,bank-change-request}/index.ts`

**Implementation.** At the top of each file:
```ts
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";
Sentry.init({
  dsn: Deno.env.get("SENTRY_EDGE_DSN"),
  environment: "production",
});
```
Wrap `Deno.serve` body in a try/catch that calls `Sentry.captureException(err)` before re-throwing.

Or simpler: each function already has a top-level try/catch — add `Sentry.captureException` inside the catch.

**Verification.** Trigger a synthetic 500 in one function. Sentry receives it.

### E.T3 — `health-check` Edge Function (daily ops alert)

**Scope.** Daily cron that scans `webhook_log.status='failed'` and `cron.job_run_details` for failures in the last 24h, emails ops if any are present.

**Files.** **NEW** `supabase/functions/health-check/index.ts`, **NEW** migration that schedules cron.

**Implementation.** Function (sketch):
```ts
const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
const { data: failed } = await supabase.from('webhook_log')
  .select('id, source, event_type, error_message, received_at')
  .eq('status', 'failed').gte('received_at', since);
const { data: cronFailed } = await supabase.from('cron.job_run_details' as any)
  .select('jobname, return_message, end_time')
  .eq('status', 'failed').gte('end_time', since);
if ((failed?.length ?? 0) === 0 && (cronFailed?.length ?? 0) === 0) {
  return jsonResponse({ status: 'green' });
}
// build HTML, sendEmail to ARL_OPS_EMAIL
```
Auth this function with the same `x-arl-cron-secret` pattern as `gallery-sync`.

Migration to schedule:
```sql
SELECT cron.schedule(
  'health-check-daily',
  '0 7 * * *', -- 07:00 UTC = 12:30 IST
  $$
    SELECT net.http_post(
      url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/health-check',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-arl-cron-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='cron_secret')
      ),
      body := '{}'::jsonb
    );
  $$
);
```

**Verification.**
- Manually invoke with the secret header. Should return `{status: 'green'}` if nothing failed in the last 24h.
- Insert a fake `webhook_log.status='failed'` row dated within 24h. Re-invoke. Should return non-green and trigger email.

**🔓 Attack test.** Call without the secret. 401.

### Stream E agent prompt

```
Apply Stream E (observability) for the Growize project. Reference:
docs/plans/2026-04-27-production-readiness-plan.md, Stream E.

Tasks:
  E.T1 Sentry on Flutter (sentry_flutter dep, init in main.dart)
  E.T2 Sentry on Edge Functions (try/catch + captureException in each)
  E.T3 health-check Edge Function (new), scheduled daily at 07:00 UTC

For E.T2, redeploy each of the 6 existing functions with Sentry init.
For E.T3, deploy the new function and apply the cron-schedule migration.

The user owes you DSN values via .env (SENTRY_DSN for Flutter,
SENTRY_EDGE_DSN for Edge). If they're missing, leave the code in but
don't fail.
```

---

## 9. Stream F — Demo persona

**PARALLEL-OK with B, D, E.**
**TOUCHES**: `lib/core/mock/demo_data.dart`, `lib/core/constants/supabase_constants.dart`, possibly a `DemoBanner` widget
**SIZE**: 1 day

### F.T1 — Promote `ARL_APP_MODE=demo` to first-class dev/QA flag

**Scope.** Today `isDemoMode = mode == 'demo' || !isConfigured`. The "or not configured" part means a misconfigured prod silently becomes demo. After Stream B.T1, that's no longer possible — but we should also make demo mode obvious to humans.

**Files.** `lib/core/constants/supabase_constants.dart`, **NEW** `lib/core/widgets/demo_mode_banner.dart` (or extend the existing `demo_badge.dart`)

**Implementation.**
- `isDemoMode` becomes only `mode == 'demo'`. (B.T1 makes the `!isConfigured` path unreachable in release.)
- Add a yellow banner at the top of every screen when `isDemoMode == true`: "DEMO MODE — no real data is shown or saved."

### F.T2 — Curated DemoInvestor data

**Scope.** Build a realistic demo persona so internal stakeholders can demo the app to investors / press without touching prod data.

**Files.** `lib/core/mock/demo_data.dart`

**Implementation.** Make `demoInvestor`, `demoProjects()`, `demoPayouts()`, `demoGalleryPhotos()`, `demoNotifications()`, `demoDocuments()` rich enough to show off:
- 2 projects (e.g., "Pineapple LLP", "Mango LLP")
- 8 payouts (mix of processed + pending, last 6 months)
- 12 gallery photos across both projects (use `assets/images/` mocks)
- 6 notifications (mix of read/unread, all 5 types)
- 4 documents (one of each `doc_type`)
- One open ticket with a 3-message conversation

Mutations in demo mode should optimistically update the in-memory state and show a toast "Demo mode — change not saved" so stakeholders see the flow without polluting prod.

**Verification.** Set `ARL_APP_MODE=demo` in `.env`. Build debug. Banner shows; every screen has rich content; submitting a ticket shows the optimistic flow.

### Stream F agent prompt

```
Build the Growize demo persona (Stream F). Reference:
docs/plans/2026-04-27-production-readiness-plan.md, Stream F.

Tasks:
  F.T1 Promote ARL_APP_MODE=demo to first-class. Visible banner on every
       screen when isDemoMode==true.
  F.T2 Curate demoInvestor + 6 demo data sets in lib/core/mock/demo_data.dart
       to a realistic level. Mutations are optimistic + show a "Demo mode"
       toast.

Don't add a separate Supabase project. Pure client-side mock.
```

---

## 10. Stream G — Red-team test suite

**PARALLEL-OK with A, B, C, D, E, F (writing). RUN AT END (against deployed system).**
**TOUCHES**: **NEW** `tests/redteam/` directory with shell scripts.
**SIZE**: 0.5 day to write, 0.5 day to run.

This stream is two halves: **G1 — write the tests** (can happen any time), and **G2 — run them after the rest of the work** (right before cutover).

### G.T1 — Setup script

`tests/redteam/setup.sh`:
```bash
#!/usr/bin/env bash
# Source this. Sets:
#   SUPABASE_URL, ANON_KEY, REAL_INVESTOR_JWT, REAL_INVESTOR_ID
# REAL_INVESTOR_JWT must be obtained by signing in as the test investor
# in the Flutter app and copying the JWT from the Supabase client (e.g.,
# via a one-time `print(client.auth.currentSession?.accessToken)`).

export SUPABASE_URL="https://oynfhdqizebvgmaoiuax.supabase.co"
export ANON_KEY="<paste anon key>"
export REAL_INVESTOR_JWT="<paste signed-in JWT>"
export REAL_INVESTOR_ID="<paste auth.uid>"
export VICTIM_INVESTOR_ID="00000000-0000-0000-0000-000000000999"
```

### G.T2 — RLS leak retest

`tests/redteam/01_rls_view_leak.sh`:
```bash
#!/usr/bin/env bash
set -e; source ./setup.sh
echo "RLS view leak retest — portfolio_summary should return only my own row."

OUT=$(curl -sS "$SUPABASE_URL/rest/v1/portfolio_summary" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT")

ROWS=$(echo "$OUT" | jq 'length')
MY_ROWS=$(echo "$OUT" | jq "[.[] | select(.investor_id == \"$REAL_INVESTOR_ID\")] | length")

[[ "$ROWS" == "$MY_ROWS" ]] && echo "✅ PASS: only my own rows" || { echo "🔴 FAIL: leaked $ROWS rows but only $MY_ROWS are mine"; exit 1; }
```

### G.T3 — Direct INSERT bypass tests

`tests/redteam/02_insert_bypass.sh`:
```bash
#!/usr/bin/env bash
set -e; source ./setup.sh

# Try POST /rest/v1/support_tickets directly with a valid JWT.
# Expected: rejected (after Day 1.6 the INSERT policy was dropped).
echo "Direct support_tickets insert (should fail)..."
RES=$(curl -sS -o /tmp/resp -w "%{http_code}" -X POST \
  "$SUPABASE_URL/rest/v1/support_tickets" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"investor_id\":\"$REAL_INVESTOR_ID\",\"category\":\"general\",\"subject\":\"bypass\",\"status\":\"open\"}")
[[ "$RES" == "401" || "$RES" == "403" || "$RES" == "42501" ]] && echo "✅ PASS ($RES)" || { echo "🔴 FAIL: got $RES"; cat /tmp/resp; exit 1; }

# Same for ticket_messages and bank_change_requests
# (same pattern, omitted for brevity)
```

### G.T4 — Edge function abuse

`tests/redteam/03_edge_fn_abuse.sh`:
```bash
#!/usr/bin/env bash
set -e; source ./setup.sh

for FN in gallery-sync onboard-investor zoho-crm-webhook; do
  echo "=== $FN: should require shared secret ==="
  RES=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/$FN" \
    -H "Content-Type: application/json" \
    -d '{}')
  [[ "$RES" == "401" ]] && echo "✅ PASS (401)" || { echo "🔴 FAIL: got $RES"; exit 1; }
done

for FN in create-ticket reply-ticket bank-change-request; do
  echo "=== $FN: should require valid Supabase JWT ==="
  # No JWT
  RES=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/$FN" \
    -H "Content-Type: application/json" -d '{}')
  [[ "$RES" == "401" ]] && echo "  ✅ no-JWT → 401" || { echo "  🔴 FAIL: got $RES without JWT"; exit 1; }
  # Bogus JWT
  RES=$(curl -sS -o /dev/null -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/$FN" \
    -H "Authorization: Bearer not-a-real-jwt" \
    -H "Content-Type: application/json" -d '{}')
  [[ "$RES" == "401" ]] && echo "  ✅ bogus-JWT → 401" || { echo "  🔴 FAIL: got $RES with bogus JWT"; exit 1; }
done
```

### G.T5 — Rate-limit / cooldown saturation

`tests/redteam/04_rate_limits.sh`:
```bash
#!/usr/bin/env bash
set -e; source ./setup.sh

# create-ticket: 5 per 24h. 6th should 429.
for i in $(seq 1 6); do
  RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/create-ticket" \
    -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
    -H "Content-Type: application/json" \
    -d "{\"category\":\"general\",\"subject\":\"rl test $i\",\"body\":\"x\"}")
  echo "  attempt $i → $RES"
  if [[ $i -le 5 ]]; then
    [[ "$RES" == "200" ]] || { echo "🔴 attempt $i should have succeeded, got $RES"; cat /tmp/r; exit 1; }
  else
    [[ "$RES" == "429" ]] || { echo "🔴 6th attempt should be 429, got $RES"; cat /tmp/r; exit 1; }
  fi
done
echo "✅ create-ticket rate limit holds"

# bank-change-request: 7-day cooldown. 2nd request while 1st is pending → 429.
# (similar; requires manual cleanup of existing pending row first)
```

### G.T6 — Storage path enumeration

`tests/redteam/05_storage_enum.sh`:
```bash
#!/usr/bin/env bash
set -e; source ./setup.sh

# Try to read a document path that's NOT mine.
echo "Documents bucket — attempting to read another investor's folder..."
RES=$(curl -sS -o /dev/null -w "%{http_code}" \
  "$SUPABASE_URL/storage/v1/object/sign/arl-documents/documents/$VICTIM_INVESTOR_ID/anything.pdf?expires_in=60" \
  -X POST \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT")
# Expected: 400 (object not found OR not allowed). Storage RLS should deny.
[[ "$RES" == "400" || "$RES" == "404" ]] && echo "✅ PASS ($RES — denied)" || { echo "🔴 FAIL: got $RES (might be a leak)"; exit 1; }

# Same for arl-gallery — try a project_id you don't have units in.
```

### G.T7 — XSS / injection in ticket fields

`tests/redteam/06_xss_injection.sh`:
```bash
#!/usr/bin/env bash
set -e; source ./setup.sh

PAYLOAD='<script>alert("XSS")</script><img src=x onerror="alert(1)">'

curl -sS -X POST "$SUPABASE_URL/functions/v1/create-ticket" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"category\":\"general\",\"subject\":\"$PAYLOAD\",\"body\":\"$PAYLOAD\"}"
echo "Now check (a) the DB row stores the literal text (b) the ops email shows the literal text, escapeHtml-ed (c) the Flutter ticket detail screen renders as text, not as HTML."
echo "Manual verification — automated only catches obvious failures."
```

### G.T8 — Auth replay / token theft simulation

`tests/redteam/07_jwt_replay.sh`:
```bash
#!/usr/bin/env bash
set -e; source ./setup.sh

# 1. Decode the JWT (informational, read-only)
echo "JWT header.payload (decoded):"
echo "$REAL_INVESTOR_JWT" | cut -d'.' -f1-2 | tr '.' '\n' | while read part; do echo "$part" | base64 -d 2>/dev/null | jq . 2>/dev/null; done

# 2. Confirm signature is needed — manually flip a byte in the payload and resign-attempt.
# (We can't really test this without the JWT signing key, but Supabase auth will reject any tampered JWT.
#  Simulate by truncating the signature segment.)
TAMPERED="${REAL_INVESTOR_JWT%.*}.AAAA"
RES=$(curl -sS -o /dev/null -w "%{http_code}" \
  "$SUPABASE_URL/rest/v1/investors?select=id&limit=1" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $TAMPERED")
[[ "$RES" == "401" ]] && echo "✅ tampered JWT rejected (401)" || { echo "🔴 FAIL: tampered JWT accepted ($RES)"; exit 1; }
```

### G.T9 — Demo-mode bypass

`tests/redteam/08_demo_bypass.sh`:
```bash
#!/usr/bin/env bash
# Build a release APK with empty .env. Install. Open. App should crash, NOT
# fall into demo mode. Manual verification — automate via:
#   1. cp .env .env.backup
#   2. echo "" > .env
#   3. flutter build apk --release
#   4. install + launch
#   5. observe crash / error screen
#   6. cp .env.backup .env
echo "Manual test: build release with empty .env, install, confirm crash on launch."
```

### G.T10 — Aggregate runner

`tests/redteam/run-all.sh`:
```bash
#!/usr/bin/env bash
set -e
cd "$(dirname "$0")"
for script in 0[1-7]_*.sh; do
  echo "=== $script ==="
  bash "$script" || { echo "🔴 Suite failed at $script"; exit 1; }
  echo
done
echo "🟢 All red-team tests passed."
```

### Stream G agent prompt

```
Write a red-team test suite for Growize (Stream G in
docs/plans/2026-04-27-production-readiness-plan.md). Output 9 shell
scripts and a runner under tests/redteam/. Each script reads from
setup.sh (which the user populates with their test JWT).

Each test asserts a specific security boundary holds. Where the test
needs human verification (XSS rendering, demo-mode crash), call that
out clearly — don't pretend to automate it.

Do NOT run the tests yet. Just write them. Running happens in Wave 3
after the rest of the work is done.
```

---

## 11. Stream H — Cutover prep + smoke walk

**SEQUENTIAL. RUNS ON DAY 7.**

### H.T1 — Run the full red-team suite

```bash
cd tests/redteam
bash run-all.sh
```

If anything fails, do not cut over.

### H.T2 — End-to-end smoke walk (real Android device + real test investor)

Walk through, in order:

1. **Onboard a test investor.** Call `onboard-investor` (Postman) with `email=test@arltech.example`, `name=Test Investor`, `arl_id=ARL-TEST-001`. Receive invite email.
2. **Open invite link.** App opens via `com.arl.app://auth`. Set password.
3. **Sign in.** Land on /home. Portfolio shows zero state (no allocations yet). Quick stats reasonable.
4. **Manually populate.** In Studio, insert one `projects` row, one `investor_units` row for the test investor, two `payouts` rows.
5. **Refresh the app.** Home shows the project; financials shows the payouts.
6. **File a ticket.** Confirm row in `support_tickets`, message in `ticket_messages`, ops email received.
7. **Reply on the ticket.** Confirm new message row, second ops email.
8. **Try to file a 6th ticket within 24h.** Confirm 429 toast.
9. **Request bank change.** Confirm row, ops email.
10. **Try a second bank change.** Confirm 429 toast.
11. **Force-update test.** Set `app_config.min_app_version = '99.0.0'`. Reopen app. Force-update screen. Reset.
12. **Maintenance mode test.** Set `maintenance_mode = 'true'`. Reopen. Maintenance screen. Reset.
13. **Sign out.** Land on /auth.
14. **Forgot password.** Receive email, click link, app opens, set new password, sign in successfully with new password.
15. **Sentry sanity.** Trigger one synthetic exception. Confirm it appears in Sentry within 1 minute.

If any step fails or shows fake data, rollback Stream A/B/C/D as needed.

### H.T3 — Cutover day (May 5)

1. **08:00 IST.** Notify ops team, finalize Zoho cutover decision.
2. **09:00 IST.** Run red-team suite one final time.
3. **09:30 IST.** Switch Zoho webhook URLs to production (from test mode).
4. **10:00 IST.** Send first wave of investor invites via `onboard-investor`.
5. **All day.** Watch Sentry, watch `webhook_log.status` for failures, watch `cron.job_run_details`.
6. **End of day.** Run `health-check` manually. Confirm green.

### H.T4 — Rollback plan (per fix)

| If broken | Rollback |
|---|---|
| `portfolio_summary` showing wrong rows | `ALTER VIEW public.portfolio_summary SET (security_invoker = off);` (reverts to status quo ante; reintroduces the leak — only do if app is hard-down) |
| `gallery-sync` cron failing | `cron.unschedule('gallery-sync-daily')` to stop attempts; investigate logs |
| Edge function regression | Each function's prior version is in repo git; deploy that |
| Migration 017 dropped policies broke writes | Re-create the 3 INSERT policies (SQL in 017's header comment) |
| Sentry rate-limiting | Reduce `tracesSampleRate` to 0.01 |

PITR is your last resort: roll the entire DB back to a known-good point-in-time.

---

## 12. Daily plan with parallel agents

Assuming 2 simultaneous agents (cheaper, lower context-switching cost).

| Day | Date | Agent 1 (you?) | Agent 2 (parallel Cowork session) | End-of-day check |
|---|---|---|---|---|
| 2 | Apr 28 | Stream A.T1 (BankDetails) | Stream C (all 5 tasks) + start G writing | A.T1 ships; migrations 018–021 in DB; 4 redteam scripts written |
| 3 | Apr 29 | Stream A.T2 (TicketDetail) | Finish G writing | A.T2 ships; full redteam suite written |
| 4 | Apr 30 | Stream B (all 7 tasks) | Stream F (demo persona) | B + F merged |
| 5 | May 1 | Stream D (perf) | Stream E (Sentry + health-check) | D + E merged |
| 6 | May 2 | (buffer / fixups) | (buffer / fixups) | Everything green |
| 7 | May 3 | Stream H.T1 + H.T2 (run redteam + smoke walk on real device) | (standby) | All tests green |
| 8 | May 4 | Pre-cutover review, last-call fixes | (standby) | Ready to ship |
| — | May 5 | Stream H.T3 (cutover + watch) | (standby) | LAUNCH |

If you can run 3 agents:

| Day | Agent 1 | Agent 2 | Agent 3 |
|---|---|---|---|
| 2 | Stream A.T1 | Stream C | Stream G writing |
| 3 | Stream A.T2 | Stream B | Stream F |
| 4 | Stream D | Stream E | (buffer) |
| 5–6 | Buffer / fixups | | |
| 7 | Stream H | | |
| 8 | Pre-cutover | | |

That's 4 days with 3 agents, leaving 4 days of buffer.

---

## 13. Final cutover checklist (May 5)

Print this. Tick each.

### T-24h
- [ ] All red-team tests pass.
- [ ] Smoke walk on real device complete.
- [ ] PITR confirmed enabled.
- [ ] Sentry receiving events from both Flutter + Edge Functions.
- [ ] `health-check` cron runs and emails green.
- [ ] `CRON_SECRET`, `ADMIN_SECRET`, `WEBHOOK_SECRET`, `RESEND_API_KEY`, `SENTRY_DSN`, `SENTRY_EDGE_DSN`, `ZOHO_*` all set on the project.
- [ ] APK signed and uploaded to Play Console (internal track).
- [ ] Ops team briefed on Studio access (`bank_change_requests`, `support_tickets`, marking statuses).

### T-2h (cutover morning)
- [ ] Run `bash tests/redteam/run-all.sh` one final time.
- [ ] Confirm `pg_policies` shape matches expected (run a snapshot query).
- [ ] Confirm `cron.job` has `gallery-sync-daily` and `health-check-daily` active.
- [ ] Confirm `vault.secrets` has `cron_secret`.
- [ ] Bank-change form, ticket form, and forgot-password each work end-to-end on the production build.

### Cutover
- [ ] Switch Zoho webhook URLs to production.
- [ ] Send first investor invite.
- [ ] Tail Sentry for 30 minutes.
- [ ] Tail `webhook_log` for the first webhook arriving from production Zoho.

### T+24h
- [ ] Daily `health-check` email received and green.
- [ ] No Sentry alerts above noise floor.
- [ ] Spot-check a few investor portfolios for accuracy.

---

## 14. Pitfalls and gotchas

- **Edge Function secrets do NOT carry across project recreates.** If you ever delete and recreate the Supabase project, every secret has to be re-set.
- **`auth.users` deletion cascades to `investors`.** If you delete an investor in Studio, do NOT delete their auth.users row first — the FK cascade does the right thing in one direction only. Always delete from `investors`, which cascades to dependent tables.
- **`vault.secrets` reads cost a Postgres query per cron tick.** That's once per day for `gallery-sync` and `health-check`. Negligible. Do NOT inline the secret into `cron.job.command` "for performance" — Vault rotation becomes painful.
- **`apply_migration` adds a row to `supabase_migrations.schema_migrations` automatically.** `execute_sql` does not. Always use `apply_migration` for DDL.
- **`supabase secrets list` shows names, not values.** If you've forgotten a value, you must re-set rather than retrieve it.
- **PITR rollback is destructive in the forward direction.** Rolling back to a point-in-time discards everything that happened after. For a brief outage that's fine; for "we want to undo a single bad row" use targeted SQL instead.
- **`flutter build apk --release` strips a lot of debug info.** If a release-only crash happens, Sentry needs the symbol files (`flutter build apk --release --obfuscate --split-debug-info=...`). Plan for that pre-launch.
- **`com.arl.app://auth` only works on Android once the app is installed.** The first invite to a fresh device opens the browser then offers to install the app, then opens the app. Don't be alarmed if your first test goes via the browser.
- **Magic links expire** (default 1 hour). Don't sit on an invite email for a day before clicking.

---

## 15. Sources of truth (where to look when something's off)

- **Schema state:** `supabase/migrations/` directory + `supabase_migrations.schema_migrations` table.
- **Policy state:** `pg_policies` view (`SELECT * FROM pg_policies WHERE schemaname='public'`).
- **Cron state:** `cron.job` table + `cron.job_run_details`.
- **Webhook state:** `webhook_log` (90-day retention via `purge-old-webhook-logs` cron).
- **Auth state:** `auth.users`, `auth.sessions`, `auth.refresh_tokens`.
- **Memory of past decisions:** `C:\Users\Sahil\AppData\Roaming\Claude\local-agent-mode-sessions\.../memory/` — see `audit_decisions.md` and `audit_phase1_findings.md`.
- **Edge Function source:** `supabase/functions/` (in repo) AND `mcp__55be8091-13df-4067-aa96-7d2cb54d2be9__get_edge_function` for what's actually deployed. After today they match; we lock in this invariant going forward.

---

## 16. End-of-document checklist

Use this to track overall progress.

### Wave 1 (parallel)
- [ ] A.T1 BankDetailsScreen wired
- [ ] A.T2 TicketDetailScreen wired
- [ ] C.T1 Migration 018 (TO authenticated)
- [ ] C.T2 Migration 019 (REVOKE wide grants)
- [ ] C.T3 Migration 020 (notifications column grants)
- [ ] C.T4 Migration 021 (combine projects policies)
- [ ] C.T5 Leaked-password protection enabled
- [ ] G.T1–T9 redteam scripts written

### Wave 2 (parallel)
- [ ] B.T1 Hard-fail dotenv in release
- [ ] B.T2 Gate dev-bypass behind kReleaseMode
- [ ] B.T3 GoRouterRefreshStream
- [ ] B.T4 Forgot-password flow
- [ ] B.T5 StorageHelper.clear() on sign-out
- [ ] B.T6 Demo fallthrough fix
- [ ] B.T7 app_config force-update gate
- [ ] D.T1 Batched signed URLs
- [ ] D.T2 unreadCount via head:true
- [ ] D.T3 Provider invalidation on auth change
- [ ] D.T4 Trim select() columns
- [ ] E.T1 Sentry on Flutter
- [ ] E.T2 Sentry on Edge Functions
- [ ] E.T3 health-check Edge Function + cron
- [ ] F.T1 Demo mode promoted + banner
- [ ] F.T2 Curated demo data

### Wave 3 (sequential)
- [ ] G.T10 Run full redteam suite — all green
- [ ] H.T1 Smoke walk on real device complete
- [ ] H.T3 Cutover checklist passed
- [ ] LAUNCH 🚀

---

*End of plan. Save the file path; this document is your reference for the next 7 days.*
