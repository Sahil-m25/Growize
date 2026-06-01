# In-app version check & "new version available" banner

The Growize Flutter app ships to investors as a sideloaded APK, so there
is no Play Store to surface updates. Instead, on every cold launch the
app pings a Supabase edge function (`latest-app-version`) which returns
the row in `app_releases` with the highest `version_code`. If that row
is ahead of the running build, the app renders a banner above the
bottom navigation: **"New version available — tap to download"**.

This document explains how ops cuts a release.

## Architecture (one line each)

* Table `public.app_releases` — one row per release. `version_code` is
  the source of truth for "newer than".
* Edge function `latest-app-version` — returns the highest-`version_code`
  row as JSON. Anonymous-callable (verify_jwt=false) so the check works
  pre-login.
* Flutter `lib/core/version/app_version_check.dart` — runs once per
  process, caches the result, swallows every error.
* Flutter `lib/core/version/version_banner.dart` — the visible widget,
  wired into `lib/core/widgets/main_scaffold.dart`.

## Current seed

A single row exists matching the v1.0 launch build:

| version_code | version_name | release_notes      |
|--------------|--------------|--------------------|
| 1            | 1.0.0        | Initial release.   |

Anything you `INSERT` with `version_code > 1` will start showing a
banner to every installed app.

## Cutting a new release (step by step)

1. **Bump `pubspec.yaml`** — the line near the top reads `version:
   1.0.0+1`. The number after `+` is the `buildNumber` the app
   reports at runtime, and is what `app_releases.version_code` must
   match-or-exceed for the banner to appear. Bump both halves
   appropriately:

   ```yaml
   version: 1.1.0+2
   ```

2. **Build the APK** locally or via CI:

   ```bash
   flutter build apk --release \
     --dart-define-from-file=.env.production
   ```

3. **Upload the APK to public storage.** Easiest path is a Supabase
   Storage bucket called `app-releases` with public read enabled.
   Create it once via the dashboard (Storage → New bucket →
   "app-releases", public). Then upload the APK and copy the public
   URL — it will look something like:

   ```
   https://oynfhdqizebvgmaoiuax.supabase.co/storage/v1/object/public/app-releases/growize-1.1.0-2.apk
   ```

   Other CDNs (R2, S3, Drive direct-download link) are fine too. The
   URL just needs to be downloadable from an Android browser without
   any extra auth.

4. **Insert a row.** Run this in the SQL editor (or via the Supabase
   MCP):

   ```sql
   INSERT INTO public.app_releases
     (version_code, version_name, apk_url, release_notes, is_critical)
   VALUES
     (2, '1.1.0',
      'https://oynfhdqizebvgmaoiuax.supabase.co/storage/v1/object/public/app-releases/growize-1.1.0-2.apk',
      'Fixed loading spinner on Financials. Faster project list.',
      false);
   ```

   That's it — within seconds, every running installation will start
   seeing the banner on its next launch (the result is cached for
   the process, so existing sessions won't see it until they restart
   the app).

5. **Optional: `web_url`.** If you also publish the build to a hosted
   web app, set `web_url` to the URL of the deployed web app. The
   banner falls back to `web_url` when `apk_url` is null.

## Critical updates

Set `is_critical = true` only for releases that meaningfully break
on older clients — security fixes, schema changes the old client
can't tolerate, etc. The behaviour change is intentionally heavy:

* The banner is rendered in `ArlColors.earth` (terracotta red) instead
  of the calmer `primary` green.
* The dismiss "X" is hidden — the user cannot close the banner.
* A modal alert pops once on app launch with **Later** and
  **Update now** buttons. "Update now" launches the APK URL in the
  external browser. "Later" closes the dialog but the strip stays
  pinned at the top.

For routine releases, leave `is_critical = false`. Use it sparingly —
it's the equivalent of pulling the alarm.

## Banner UX summary

Non-critical (default):

> **New version available — tap to download**   v1.1.0   [×]

Critical (`is_critical = true`):

> **New version available — tap to download**   v1.1.0
>
> (no dismiss button; modal alert: "Update required —
> Version 1.1.0 is required to continue. [Later] [Update now]")

## Failure modes

The version check is best-effort and silent. If the edge function is
down, the network is blocked, the JSON is malformed, the URL is
broken, etc., the banner just doesn't show. There is no toast, no
log surfaced to the user, no Sentry breadcrumb. This is by design:
investors must never see a noisy "version check failed" error.

If you suspect the check is failing, hit the function directly:

```bash
curl https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/latest-app-version
```

Expected response:

```json
{
  "version_code": 1,
  "version_name": "1.0.0",
  "apk_url": null,
  "web_url": null,
  "release_notes": "Initial release.",
  "is_critical": false
}
```

If the table is empty, the function returns `{"version_code": 0, ...}`
and the app stays silent (it interprets 0 as "no release published").

## RLS posture

`app_releases` has RLS enabled with one policy: authenticated users
can `SELECT`. The edge function itself uses the service role so
unauthenticated callers (pre-login cold starts) still get a result.
There is no insert/update/delete policy — ops makes changes via
the dashboard / SQL editor / MCP using the service role.
