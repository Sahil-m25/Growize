# ARL Investor App — Supabase setup (Windows / PowerShell).
# Run this from the project root after `supabase login` + `supabase link`.
#
# What it does:
#   1. Creates storage buckets arl-documents and arl-gallery (private).
#   2. Pushes migration 013 (storage RLS policies).
#   3. Sets the required Vault secrets (you supply values via env or prompts).
#   4. Deploys the six P0/P1 Edge Functions.
#
# Idempotent — safe to re-run.

$ErrorActionPreference = "Stop"

Write-Host "ARL Supabase setup" -ForegroundColor Cyan
Write-Host ""

# ── 1. Buckets ─────────────────────────────────────────────────────────
Write-Host "Creating storage buckets..." -ForegroundColor Yellow
supabase storage buckets create arl-documents --private 2>$null
supabase storage buckets create arl-gallery --private 2>$null
Write-Host "  OK" -ForegroundColor Green

# ── 2. Storage RLS migration ───────────────────────────────────────────
Write-Host "Applying migration 013_storage_rls.sql..." -ForegroundColor Yellow
supabase db push
Write-Host "  OK" -ForegroundColor Green

# ── 3. Vault secrets ───────────────────────────────────────────────────
Write-Host "Setting Vault secrets (skip ones you've already set)..." -ForegroundColor Yellow

function Set-SecretIfMissing {
  param([string]$Name, [string]$Prompt)
  $existing = supabase secrets list 2>$null | Select-String -Pattern "^$Name "
  if ($existing) { Write-Host "  $Name already set — skipping" -ForegroundColor Gray; return }
  $val = Read-Host "  $Prompt (empty = skip)"
  if ($val) { supabase secrets set "$Name=$val" | Out-Null; Write-Host "  $Name set" -ForegroundColor Green }
  else      { Write-Host "  $Name skipped" -ForegroundColor Gray }
}

Set-SecretIfMissing -Name "ADMIN_SECRET"        -Prompt "ADMIN_SECRET (random hex, e.g. openssl rand -hex 16)"
Set-SecretIfMissing -Name "WEBHOOK_SECRET"      -Prompt "WEBHOOK_SECRET (random hex)"
Set-SecretIfMissing -Name "ZOHO_CLIENT_ID"      -Prompt "ZOHO_CLIENT_ID"
Set-SecretIfMissing -Name "ZOHO_CLIENT_SECRET"  -Prompt "ZOHO_CLIENT_SECRET"
Set-SecretIfMissing -Name "ZOHO_REFRESH_TOKEN"  -Prompt "ZOHO_REFRESH_TOKEN"
Set-SecretIfMissing -Name "ARL_OPS_EMAIL"       -Prompt "ARL_OPS_EMAIL (e.g. ops@agresearchlabs.com)"
Set-SecretIfMissing -Name "RESEND_API_KEY"      -Prompt "RESEND_API_KEY"

# ── 4. Deploy Edge Functions ───────────────────────────────────────────
Write-Host "Deploying Edge Functions..." -ForegroundColor Yellow
supabase functions deploy onboard-investor   --no-verify-jwt
supabase functions deploy zoho-crm-webhook   --no-verify-jwt
supabase functions deploy gallery-sync       --no-verify-jwt
supabase functions deploy create-ticket
supabase functions deploy reply-ticket
supabase functions deploy bank-change-request
Write-Host "  OK" -ForegroundColor Green

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
Write-Host "Next steps:"
Write-Host "  1. Schedule gallery-sync via SQL (see supabase/functions/gallery-sync/README.md)"
Write-Host "  2. Configure Zoho CRM workflow rules (see supabase/functions/zoho-crm-webhook/README.md)"
Write-Host "  3. Test onboard-investor by inviting a real investor"
