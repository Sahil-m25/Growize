# gallery-sync

P1 — daily cron pull of farm photos from Zoho CRM into the `arl-gallery` storage bucket.

## Deploy

```bash
supabase functions deploy gallery-sync --no-verify-jwt
```

## Required Vault secrets

- `ZOHO_REFRESH_TOKEN`, `ZOHO_CLIENT_ID`, `ZOHO_CLIENT_SECRET` — for OAuth refresh.
- (Optional) `ZOHO_SERVICE_TOKEN` — long-lived token; if set, skips refresh.
- The function uses the `arl-gallery` bucket and `gallery_photos` table — both must exist (see migration 013 + setup script).

## Schedule

Run in SQL editor after deploy:

```sql
SELECT cron.schedule(
  'gallery-sync-daily',
  '30 0 * * *',  -- 00:30 UTC = 06:00 IST
  $$
  SELECT net.http_post(
    url := 'https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/gallery-sync',
    headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.service_role_key'))
  );
  $$
);
```

You'll need `pg_cron` and `pg_net` extensions enabled (Dashboard → Database → Extensions).

## Idempotency

Each Zoho attachment has a unique `zoho_file_id`. We `SELECT` known IDs before downloading and only insert new ones. Re-runs are safe.
