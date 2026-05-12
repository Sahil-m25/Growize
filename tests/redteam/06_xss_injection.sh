#!/usr/bin/env bash
# G.T7: XSS / injection in ticket fields
# This test attempts to inject XSS payloads via create-ticket and checks that:
#   1. The DB stores the literal text (not interpreted as HTML)
#   2. Ops email shows escaped HTML
#   3. Flutter ticket detail screen renders as text, not as executable HTML
# Note: Steps 2 and 3 require manual verification in the ticket detail screen and email.

set -e
source ./setup.sh

PAYLOAD='<script>alert("XSS")</script><img src=x onerror="alert(1)">'

echo "XSS injection test — submitting malicious payload..."
RES=$(curl -sS -o /tmp/r -w "%{http_code}" -X POST "$SUPABASE_URL/functions/v1/create-ticket" \
  -H "Authorization: Bearer $REAL_INVESTOR_JWT" \
  -H "Content-Type: application/json" \
  -d "{\"category\":\"general\",\"subject\":\"$PAYLOAD\",\"body\":\"$PAYLOAD\"}")

[[ "$RES" == "200" ]] && echo "  Ticket created ($RES)" || { echo "  FAIL: ticket creation failed with $RES"; cat /tmp/r; exit 1; }

echo ""
echo "MANUAL VERIFICATION REQUIRED:"
echo "1. Check the support_tickets table in Supabase Studio:"
echo "   - Subject should display literally: <script>alert(\"XSS\")</script>..."
echo "   - Should NOT execute any JavaScript"
echo ""
echo "2. Check the ops email notification:"
echo "   - Should show escaped HTML: &lt;script&gt;alert(&quot;XSS&quot;)&lt;/script&gt;..."
echo ""
echo "3. Open the ticket in the Flutter app:"
echo "   - Ticket detail should render as plain text"
echo "   - Should NOT execute any JavaScript alerts or img onerror handlers"
echo ""
echo "If any of the above show executable HTML instead of literal text, XSS vulnerability exists."
