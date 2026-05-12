#!/usr/bin/env bash
# G.T5: Rate-limit / cooldown saturation
# Tests that:
#   - create-ticket: 5 per 24h limit enforced (6th request returns 429)
#   - bank-change-request: 7-day cooldown enforced (2nd request while 1st pending returns 429)
# WARNING: This test consumes part of the 5/24h ticket creation budget.

set -e
source ./setup.sh

echo "Testing create-ticket rate limit (5 per 24h)..."
echo "Attempting 6 ticket creations (first 5 should succeed, 6th should be 429)..."

for i in $(seq 1 6); do
  RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
    "$SUPABASE_URL/functions/v1/create-ticket" \
    -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
    -H "Content-Type: application/json" \
    -d "{\"category\":\"general\",\"subject\":\"rate-limit test $i\",\"body\":\"automated test\"}")
  echo "  attempt $i → $RES"
  if [[ $i -le 5 ]]; then
    [[ "$RES" == "200" ]] || { echo "    FAIL: attempt $i should have succeeded, got $RES"; cat /tmp/r; exit 1; }
  else
    [[ "$RES" == "429" ]] || { echo "    FAIL: 6th attempt should be 429, got $RES"; cat /tmp/r; exit 1; }
  fi
done

echo "PASS: create-ticket rate limit enforced"

echo ""
echo "Testing bank-change-request cooldown..."
echo "NOTE: This test requires a clean state (no pending bank_change_request from this investor in the last 7 days)."
echo "If this test fails due to existing pending requests, manually delete old bank_change_requests from the investor in Studio."
echo "Attempting first bank change request..."

RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
  "$SUPABASE_URL/functions/v1/bank-change-request" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"new_account_holder_name\":\"Test User\",\"new_ifsc_code\":\"SBIN0001234\",\"new_account_number\":\"12345678901234\"}")
[[ "$RES" == "200" ]] && echo "  PASS: first request accepted (200)" || { echo "  FAIL: first request failed with $RES"; cat /tmp/r; exit 1; }

echo "Attempting second bank change request (should be rejected due to cooldown)..."
RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
  "$SUPABASE_URL/functions/v1/bank-change-request" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"new_account_holder_name\":\"Another User\",\"new_ifsc_code\":\"HDFC0001234\",\"new_account_number\":\"98765432109876\"}")
[[ "$RES" == "429" ]] && echo "  PASS: second request rejected (429)" || { echo "  FAIL: second request should be 429, got $RES"; cat /tmp/r; exit 1; }

echo "PASS: bank-change-request cooldown enforced"
