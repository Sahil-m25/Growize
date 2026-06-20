-- ============================================================
-- MIGRATION 064 — app_releases table (PR-D, E-4 + E-5)
--
-- The latest-app-version Edge Function reads from `app_releases` but
-- no migration in the repository creates the table (verified by
-- searching `supabase/migrations/` and `supabase/migrations_archive_20260608/`
-- — the only references to `app_releases` are inside the function
-- itself). Until today the function's `maybeSingle()` quietly returned
-- null on every call and the app treated itself as up-to-date.
--
-- This migration creates the table with three channels
-- (android / ios / web), enforces channel-URL pairing via a CHECK
-- constraint (web rows have web_url, native rows have apk_url —
-- prevents "I have an APK but no web URL" or vice versa), and
-- enables RLS so anon + authenticated can read but only service_role
-- can write.
--
-- A unique (channel, version_code) prevents accidental duplicate
-- releases for the same platform.
--
-- A v1 backfill row per channel is inserted so the function returns
-- something on first deploy. Update the URLs before production.
--
-- Reversible:
--   DROP TABLE public.app_releases;
-- ============================================================

create table if not exists public.app_releases (
  id              uuid primary key default gen_random_uuid(),
  channel         text not null check (channel in ('android', 'ios', 'web')),
  version_code    int  not null check (version_code > 0),
  version_name    text not null,
  apk_url         text,
  web_url         text,
  release_notes   text,
  is_critical     boolean not null default false,
  published_at    timestamptz not null default now(),
  -- Channel-URL pairing: web rows MUST have web_url and MUST NOT have
  -- apk_url; native rows MUST have apk_url and MUST NOT have web_url.
  -- This stops ops from publishing a half-filled row.
  constraint app_releases_url_pairing check (
    (channel =  'web'    and apk_url is null     and web_url is not null) or
    (channel in ('android','ios') and apk_url is not null and web_url is null)
  )
);

-- Unique (channel, version_code) so the same version_code can exist
-- once per channel (Android v2, iOS v2, Web v2) but never twice for
-- the same platform.
create unique index if not exists app_releases_channel_version_uniq
  on public.app_releases (channel, version_code);

create index if not exists app_releases_channel_published_idx
  on public.app_releases (channel, published_at desc);

alter table public.app_releases enable row level security;

-- Public read so the anon latest-app-version function call can see
-- the row. The function reads the latest published release for the
-- caller's platform; this policy exposes nothing PII (no name, no
-- phone, no email — just version metadata + URLs).
drop policy if exists "app_releases: public read" on public.app_releases;
create policy "app_releases: public read"
  on public.app_releases
  for select
  to anon, authenticated
  using (true);

-- No INSERT/UPDATE/DELETE policy for anon or authenticated — only
-- service_role can write. The default `revoke ... from anon,
-- authenticated` from migration 019 covers DML.
grant select on public.app_releases to anon, authenticated;

-- Backfill: one v1 release per channel so the function returns
-- something on first deploy. Replace the URLs with the real ones
-- before going to production.
insert into public.app_releases (channel, version_code, version_name, apk_url, release_notes)
values
  ('android', 1, '1.0.0',
   'https://github.com/agresearchlabs/growize/releases/download/v1.0.0/app-release.apk',
   'Initial release.'),
  ('ios',     1, '1.0.0',
   'https://apps.apple.com/in/app/growize/id000000000',
   'Initial release.')
on conflict (channel, version_code) do nothing;

insert into public.app_releases (channel, version_code, version_name, web_url, release_notes)
values
  ('web',     1, '1.0.0',
   'https://app.growize.in',
   'Initial release.')
on conflict (channel, version_code) do nothing;

comment on table public.app_releases is
  'Per-channel app release metadata. The latest-app-version Edge '
  'Function reads the latest published row for the caller''s platform '
  'and returns version_code + apk_url (android/ios) or web_url (web). '
  'Public-read RLS; service_role-only writes. Channel-URL pairing '
  'enforced by CHECK constraint.';

comment on column public.app_releases.channel is
  'Platform: android | ios | web. PR-D adds this filter so a web '
  'user does not receive an Android APK and vice versa.';

comment on column public.app_releases.is_critical is
  'When true, the Flutter app should force the user to update '
  'before allowing further interaction. The function returns this '
  'flag to the client.';

-- Sanity / verification queries (run manually post-apply):
--
-- 1. Constraint present:
--    SELECT conname FROM pg_constraint
--     WHERE conrelid = 'public.app_releases'::regclass
--       AND contype = 'c';
--    -- Must include 'app_releases_url_pairing'.
--
-- 2. RLS enabled:
--    SELECT relname, relrowsecurity FROM pg_class
--     WHERE relname = 'app_releases';
--    -- relrowsecurity = t.
--
-- 3. Backfill rows present:
--    SELECT channel, version_code, version_name FROM public.app_releases
--     ORDER BY channel, version_code;
--    -- Expect 3 rows: android/1, ios/1, web/1.
