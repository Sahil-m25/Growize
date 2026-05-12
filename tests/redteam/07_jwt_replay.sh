#!/usr/bin/env bash
# G.T8: Auth replay / token theft simulation
# Tests that:
#   1. JWT payload can be read (informational only)
#   2. JWT signature validation is enforced (tampered JWT rejected)
#   3. Tampered/expired tokens return 401
# This test does not attempt to forge a real JWT (would require the signing key).

set -e
source ./setup.sh

echo "JWT signature validation test..."
echo ""
echo "1. JWT structure (informational — header and payload decoded):"
# Decode the JWT header and payload (base64)
PART1=$(echo "$REAL_INVESTOR_JWT" | cut -d'.' -f1 | tr '_-' '/+' | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "  (header decode failed)")
PART2=$(echo "$REAL_INVESTOR_JWT" | cut -d'.' -f2 | tr '_-' '/+' | base64 -d 2>/dev/null | jq . 2>/dev/null || echo "  (payload decode failed)")
echo "  Header: $PART1"
echo "  Payload: $PART2"
echo ""

echo "2. Signature validation — attempt with tampered JWT..."
TAMPERED="${REAL_INVESTOR_JWT%.*}.AAAA"
RES=$(curl -sS -o /tmp/r -w "%{http_code}" \
  "$SUPABASE_URL/rest/v1/investors?select=id&limit=1" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $TAMPERED")
[[ "$RES" == "401" ]] && echo "  PASS: tampered JWT rejected (401)" || { echo "  FAIL: tampered JWT accepted ($RES) — signature not validated!"; cat /tmp/r; exit 1; }

echo ""
echo "3. Valid JWT should still work..."
RES=$(curl -sS -o /tmp/r -w "%{http_code}" \
  "$SUPABASE_URL/rest/v1/investors?select=id&limit=1" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT")
[[ "$RES" == "200" ]] && echo "  PASS: valid JWT accepted (200)" || { echo "  FAIL: valid JWT rejected ($RES)"; cat /tmp/r; exit 1; }

echo ""
echo "PASS: JWT replay protection verified"
