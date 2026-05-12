#!/usr/bin/env bash
# G.T3: Direct INSERT bypass tests
# Expected: Direct POST to /rest/v1/ endpoints should be rejected (all INSERT
# policies removed from support_tickets, ticket_messages, bank_change_requests).
# These tables only allow writes via Edge Functions, which enforce additional
# validation (rate limits, authorization, etc.).

set -e
source ./setup.sh

echo "Direct support_tickets insert (should fail)..."
RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
  "$SUPABASE_URL/rest/v1/support_tickets" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"investor_id\":\"$REAL_INVESTOR_ID\",\"category\":\"general\",\"subject\":\"bypass\",\"status\":\"open\"}")
[[ "$RES" == "401" || "$RES" == "403" || "$RES" == "42501" ]] && echo "  PASS ($RES)" || { echo "  FAIL: got $RES"; cat /tmp/r; exit 1; }

echo "Direct ticket_messages insert (should fail)..."
RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
  "$SUPABASE_URL/rest/v1/ticket_messages" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"ticket_id\":\"00000000-0000-0000-0000-000000000001\",\"investor_id\":\"$REAL_INVESTOR_ID\",\"message\":\"bypass\"}")
[[ "$RES" == "401" || "$RES" == "403" || "$RES" == "42501" ]] && echo "  PASS ($RES)" || { echo "  FAIL: got $RES"; cat /tmp/r; exit 1; }

echo "Direct bank_change_requests insert (should fail)..."
RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST \
  "$SUPABASE_URL/rest/v1/bank_change_requests" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"investor_id\":\"$REAL_INVESTOR_ID\",\"new_account_holder_name\":\"bypass\",\"new_ifsc_code\":\"BYPASS\"}")
[[ "$RES" == "401" || "$RES" == "403" || "$RES" == "42501" ]] && echo "  PASS ($RES)" || { echo "  FAIL: got $RES"; cat /tmp/r; exit 1; }

echo "PASS: all direct INSERT attempts rejected"
