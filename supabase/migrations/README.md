# Migrations

This directory holds the source-of-truth SQL migrations for the Growize
Supabase database (`oynfhdqizebvgmaoiuax`).

## Filename convention

`<14-digit-version>_<name>.sql` — matches what the Supabase CLI writes
to `supabase_migrations.schema_migrations.version`. Files use this
exact prefix so `supabase db push` will recognise them as already
applied (and skip them) when the live DB has the same version.

## History

These files were materialised from
`supabase_migrations.schema_migrations` on **2026-04-27** during a
backend audit. Before that date, the repo contained only one
hand-crafted file (`013_storage_rls.sql`) which did **not** match the
live state — see the deprecation note inside that file.

If you need to re-create this database from scratch:

```bash
supabase db reset      # local dev DB
supabase db push       # apply all files in this directory in order
```

## Adding new migrations

```bash
supabase migration new <name>
# edit the created file
supabase db push
```

The CLI will assign the next 14-digit timestamp and write it into
`supabase_migrations.schema_migrations` after a successful push.

## Notes for future-you

- `015_security_invoker_portfolio_summary` (2026-04-27) closed a
  PII-leaking view bug. The view returns one row per investor and
  relies on RLS on `investor_units` and `payouts`. Do **not**
  change it back to `security_invoker = off`.
- `014_enable_pg_cron_and_schedule` schedules `gallery-sync` daily
  at 00:30 UTC. The Authorization header in this file references
  `current_setting('app.settings.service_role_key', true)`. If that
  GUC isn't set on the project, the cron call will go out without
  auth. A follow-up migration adds an `x-arl-cron-secret` header
  and removes the dependency on the GUC.
