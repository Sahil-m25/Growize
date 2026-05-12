#!/usr/bin/env bash
# G.T4: Edge function abuse / authentication
# Tests that:
#   - gallery-sync, onboard-investor, zoho-crm-webhook require x-arl-cron-secret
#   - create-ticket, reply-ticket, bank-change-request require valid Supabase JWT
# Expected: all requests without proper auth return 401.

set -e
source ./setup.sh

echo "Testing cron-secret-protected functions (gallery-sync, onboard-investor, zoho-crm-webhook)..."
for FN in gallery-sync onboard-investor zoho-crm-webhook; do
  echo "  $FN: should require shared secret"
  RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/$FN" \
    -H "Content-Type: application/json" \
    -d '{}')
  [[ "$RES" == "401" ]] && echo "    PASS (401)" || { echo "    FAIL: got $RES"; cat /tmp/r; exit 1; }
done

echo "Testing JWT-protected functions (create-ticket, reply-ticket, bank-change-request)..."
for FN in create-ticket reply-ticket bank-change-request; do
  echo "  $FN: should require valid Supabase JWT"

  # No JWT
  RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/$FN" \
    -H "Content-Type: application/json" -d '{}')
  [[ "$RES" == "401" ]] && echo "    PASS: no-JWT → 401" || { echo "    FAIL: got $RES without JWT"; cat /tmp/r; exit 1; }

  # Bogus JWT
  RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/$FN" \
    -H "Authorization: Bearer not-a-real-jwt" \
    -H "Content-Type: application/json" -d '{}')
  [[ "$RES" == "401" ]] && echo "    PASS: bogus-JWT → 401" || { echo "    FAIL: got $RES with bogus JWT"; cat /tmp/r; exit 1; }
done

echo "PASS: all edge function auth checks passed"
