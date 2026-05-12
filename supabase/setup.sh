#!/usr/bin/env bash
# ARL Investor App — Supabase setup (POSIX shells / macOS / Linux).
# Run from project root after `supabase login` + `supabase link`.
#
# Idempotent.

set -euo pipefail

echo "ARL Supabase setup"
echo

# ── 1. Buckets ─────────────────────────────────────────────────────────
echo "Creating storage buckets..."
supabase storage buckets create arl-documents --private 2>/dev/null || true
supabase storage buckets create arl-gallery   --private 2>/dev/null || true
echo "  OK"

# ── 2. Storage RLS migration ───────────────────────────────────────────
echo "Applying migrations..."
supabase db push
echo "  OK"

# ── 3. Vault secrets ───────────────────────────────────────────────────
set_secret_if_missing() {
  local name="$1"; local prompt="$2"
  if supabase secrets list 2>/dev/null | grep -q "^$name "; then
    echo "  $name already set — skipping"
    return
  fi
  read -r -p "  $prompt (empty = skip): " val
  if [ -n "$val" ]; then
    supabase secrets set "$name=$val" >/dev/null
    echo "  $name set"
  else
    echo "  $name skipped"
  fi
}

echo "Setting Vault secrets..."
set_secret_if_missing ADMIN_SECRET       "ADMIN_SECRET (e.g. openssl rand -hex 16)"
set_secret_if_missing WEBHOOK_SECRET     "WEBHOOK_SECRET (random hex)"
set_secret_if_missing ZOHO_CLIENT_ID     "ZOHO_CLIENT_ID"
set_secret_if_missing ZOHO_CLIENT_SECRET "ZOHO_CLIENT_SECRET"
set_secret_if_missing ZOHO_REFRESH_TOKEN "ZOHO_REFRESH_TOKEN"
set_secret_if_missing ARL_OPS_EMAIL      "ARL_OPS_EMAIL"
set_secret_if_missing RESEND_API_KEY     "RESEND_API_KEY"

# ── 4. Deploy Edge Functions ───────────────────────────────────────────
echo "Deploying Edge Functions..."
supabase functions deploy onboard-investor   --no-verify-jwt
supabase functions deploy zoho-crm-webhook   --no-verify-jwt
supabase functions deploy gallery-sync       --no-verify-jwt
supabase functions deploy create-ticket
supabase functions deploy reply-ticket
supabase functions deploy bank-change-request
echo "  OK"

cat <<EOF

Done.
Next steps:
  1. Schedule gallery-sync via SQL (supabase/functions/gallery-sync/README.md)
  2. Configure Zoho CRM workflow rules (supabase/functions/zoho-crm-webhook/README.md)
  3. Test onboard-investor by inviting a real investor
EOF
