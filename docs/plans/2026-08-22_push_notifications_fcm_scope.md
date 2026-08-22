# Native push notifications — scope

**Status:** not started. Scoped 2026-08-22 as the follow-up to the in-app
`phase_update` work (migration 066).

## Where we actually are

Push is not partially built. It is not built at all. The audit found:

| Piece | State |
|---|---|
| `lib/core/notifications/fcm_service.dart` | 7-line stub — `static Future<void> init() async {}` |
| `firebase_messaging` / `flutter_local_notifications` | absent from `pubspec.yaml` |
| `android/app/google-services.json` | absent |
| `ios/Runner/GoogleService-Info.plist` | absent |
| `POST_NOTIFICATIONS` permission (Android 13+) | absent from `AndroidManifest.xml` |
| `device_tokens` table | absent |
| `notify-push` edge function | absent |
| Web push service worker | absent from `web/` |

`docs/ops/v1.1_roadmap.md:127` already records this as a deliberate v1.2
deferral, and `supabase/migrations_archive_20260608/…_006_notifications_support_bank.sql`
was written to keep the `notifications` table future-proof for it.

The consequence today: **every notification the app produces is
delivery-on-open.** There is no realtime subscription on `notifications`
either (only `ticket_detail_screen.dart` opens a realtime channel), so a
stage update reaches an investor whenever they next launch the app —
which for an investor portal could be weeks.

## What it takes

### 1. Firebase project + Android config
- Create the Firebase project, register the Android package, download
  `google-services.json` into `android/app/`.
- Add the `com.google.gms.google-services` Gradle plugin.
- **Check first:** the app currently ships no Firebase dependency at all,
  so this also pulls in `firebase_core`. Confirm that does not collide
  with the existing Sentry setup or bloat the APK past whatever size
  budget the email-attached distribution can carry.

### 2. Flutter client
- `firebase_messaging` + `flutter_local_notifications` (the latter for
  foreground presentation — FCM does not show a banner while the app is
  open).
- Replace the `FcmService` stub: request permission (Android 13+ needs
  the runtime prompt), fetch the token, register it, handle refresh,
  handle taps, route from `metadata.cta_route` — which the migration-066
  trigger already populates, so deep-linking comes free.
- Wire `notifications_enabled` from `user_settings` to actually gate
  something. Today that toggle in Profile > Security governs nothing;
  after migration 066 it gates the in-app feed, and it should gate push
  too.

### 3. Backend
- `device_tokens` table: `(investor_id, token, platform, last_seen_at)`,
  unique on token, RLS so an investor only writes their own rows.
- `notify-push` edge function: takes a notification row, looks up the
  investor's tokens, posts to FCM v1 (needs a service-account JWT, not
  the legacy server key — that was decommissioned).
- A trigger or `pg_net` call on `notifications INSERT` to invoke it. The
  consultation flow in `notify_consultation_request()` already
  demonstrates the `pg_net` pattern to copy.
- Token cleanup on `UNREGISTERED` / `NOT_FOUND` responses, otherwise the
  table fills with dead tokens from reinstalled apps.

### 4. Distribution — the real constraint
Push only reaches users who install a **new build**. Per the v1.1
roadmap the current distribution channel is an emailed APK, not the Play
Store. So shipping push means getting every existing investor to install
a fresh APK, and until they do they stay on in-app-only delivery. The
"new version available" banner queued in the roadmap (item 1, backed by
the `app_releases` table from migration 064) is arguably a prerequisite —
without it there is no way to tell stale installs to update.

iOS is blocked separately: no signing certificates yet, so APNs cannot be
configured at all.

## Rough shape of the work

| Chunk | Notes |
|---|---|
| Firebase + Android config | small, mostly console clicking |
| `FcmService` implementation | medium — permission, token lifecycle, foreground vs background, tap routing |
| `device_tokens` + RLS | small |
| `notify-push` + FCM v1 auth | medium — service-account JWT signing inside an edge function is the fiddly part |
| Token cleanup | small, but skipping it hurts later |
| QA across app states | medium — foreground / background / killed behave differently and all three need testing on a real device |
| Rollout | gated on the update-banner work above |

## Decisions needed before starting

1. **Android-only first, or wait for iOS?** iOS needs signing certs that
   do not exist yet. Android-first means push behaviour differs by
   platform for a while.
2. **Play Store or keep emailing APKs?** If push matters, the Store makes
   the update path far less painful.
3. **Does the update banner ship first?** Recommended — otherwise stale
   installs silently never get push and there is no way to nudge them.
4. **Which notification types warrant a push?** Pushing all eleven types
   will feel spammy. Payouts and stage updates are plausible; document
   syncs and photo batches probably are not.
