# supabase/ — Backend deploy artefacts

| Folder | What |
|---|---|
| `migrations/` | New migrations applied via `supabase db push`. Existing 001–012 already live. |
| `functions/` | Edge Function source (Deno/TypeScript). |
| `setup.ps1` / `setup.sh` | One-shot bootstrap — buckets + RLS + secrets + functions deploy. |

## First-time setup

```bash
supabase login
supabase link --project-ref oynfhdqizebvgmaoiuax

# Windows
.\supabase\setup.ps1

# macOS / Linux
chmod +x supabase/setup.sh
./supabase/setup.sh
```

After the script:

1. **Schedule the gallery-sync cron** (one-time) — see `functions/gallery-sync/README.md`.
2. **Configure Zoho CRM workflow rules** for the three modules (see `functions/zoho-crm-webhook/README.md`).
3. Smoke test by calling `onboard-investor` with a test email.

## Re-running

The setup script is idempotent — buckets, secrets, and function deploys are all upserts.
