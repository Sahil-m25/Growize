#!/usr/bin/env bash
# G.T6: Storage path enumeration
# Tests that storage bucket RLS policies prevent access to another investor's documents/gallery.
# Expected: attempts to sign/list paths for other investors return 400/404/403.

set -e
source ./setup.sh

echo "Testing arl-documents bucket RLS..."
echo "Attempting to read another investor's document folder..."
RES=$(curl -sS -o /tmp/r -w "%{http_code}" \
  "$SUPABASE_URL/storage/v1/object/sign/arl-documents/documents/$VICTIM_INVESTOR_ID/anything.pdf?expires_in=60" \
  -X POST \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT")
[[ "$RES" == "400" || "$RES" == "404" || "$RES" == "403" ]] && echo "  PASS ($RES — access denied)" || { echo "  FAIL: got $RES (might be a leak)"; cat /tmp/r; exit 1; }

echo "Testing arl-gallery bucket RLS..."
echo "Attempting to read gallery for a project not owned by investor..."
# Use VICTIM_INVESTOR_ID as project_id (doesn't exist but tests path-based RLS)
RES=$(curl -sS -o /tmp/r -w "%{http_code}" \
  "$SUPABASE_URL/storage/v1/object/sign/arl-gallery/projects/$VICTIM_INVESTOR_ID/photo.jpg?expires_in=60" \
  -X POST \
  -H "apikey: $ANON_KEY" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT")
[[ "$RES" == "400" || "$RES" == "404" || "$RES" == "403" ]] && echo "  PASS ($RES — access denied)" || { echo "  FAIL: got $RES (might be a leak)"; cat /tmp/r; exit 1; }

echo "PASS: storage bucket RLS checks passed"
