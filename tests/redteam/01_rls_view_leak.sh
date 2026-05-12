#!/usr/bin/env bash
# G.T2: RLS view leak retest
# Expected: portfolio_summary view returns only rows for the authenticated investor.
# If this test fails, a row from another investor leaked through RLS.

set -e
source ./setup.sh

echo "RLS view leak retest — portfolio_summary should return only my own row."

OUT=$(curl -sS "$SUPABASE_URL/rest/v1/portfolio_summary" \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT")

ROWS=$(echo "$OUT" | jq 'length')
MY_ROWS=$(echo "$OUT" | jq "[.[] | select(.investor_id == \"$REAL_INVESTOR_ID\")] | length")

[[ "$ROWS" == "$MY_ROWS" ]] && echo "PASS: only my own rows" || { echo "FAIL: leaked $ROWS rows but only $MY_ROWS are mine"; cat /tmp/r; exit 1; }
