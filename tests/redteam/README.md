# Red-Team Test Suite for Growize

This directory contains security and resilience tests for the Growize Supabase backend and API layer. Tests are designed to run against a **live deployment** and verify that critical security boundaries hold.

## Setup

### 1. Populate `setup.sh` with test credentials

Before running any test, you must populate `setup.sh` with:
- `ANON_KEY` — Supabase anon API key (from Studio → Project Settings → API)
- `REAL_INVESTOR_JWT` — Access token of a test investor (from Flutter app)
- `REAL_INVESTOR_ID` — Auth UID of the test investor (from Flutter app)

**How to get JWT and ID:**

1. Sign in to the Flutter app as a test investor account (e.g., `test@arltech.example`).
2. In the Flutter app, add a debug print to capture the JWT and auth UID:
   ```dart
   // Add to main.dart or a login screen after auth is complete:
   print('JWT: ${client.auth.currentSession?.accessToken}');
   print('UID: ${client.auth.currentUser?.id}');
   ```
3. Run the app in debug mode, sign in, and copy the printed values.
4. Paste into `setup.sh`:
   ```bash
   export REAL_INVESTOR_JWT="<paste JWT here>"
   export REAL_INVESTOR_ID="<paste UID here>"
   ```

### 2. Populate ANON_KEY

In Supabase Studio:
- Go to **Project Settings** → **API**
- Copy the **anon public key** (not the service role key)
- Paste into `setup.sh`

## Test Files

| Script | Test | Expected Result |
|--------|------|-----------------|
| `01_rls_view_leak.sh` | RLS view leak (G.T2) | `portfolio_summary` returns only investor's own rows |
| `02_insert_bypass.sh` | Direct INSERT bypass (G.T3) | Direct table POSTs return 401/403/42501 |
| `03_edge_fn_abuse.sh` | Edge function auth (G.T4) | Functions reject requests without proper auth (cron-secret or JWT) |
| `04_rate_limits.sh` | Rate limits / cooldown (G.T5) | `create-ticket` 6th attempt → 429; `bank-change-request` 2nd attempt → 429 |
| `05_storage_enum.sh` | Storage enumeration (G.T6) | Other investors' storage paths return 400/404/403 |
| `06_xss_injection.sh` | XSS payloads (G.T7) | Payloads stored as literal text; manual verification of email + app rendering |
| `07_jwt_replay.sh` | JWT validation (G.T8) | Tampered JWT rejected; valid JWT accepted |
| `08_demo_bypass.sh` | Demo mode fallthrough (G.T9) | **MANUAL**: Release build with empty .env crashes (does not enter demo mode) |

## Running Tests

### Run all automated tests (01–07)

```bash
cd tests/redteam
bash run-all.sh
```

This runs tests 01–07 in sequence. If any test fails, the suite stops.

### Run a single test

```bash
cd tests/redteam
source ./setup.sh
bash 01_rls_view_leak.sh
```

### Run the manual demo-bypass test (08)

```bash
bash 08_demo_bypass.sh
```

This prints instructions for the manual verification. Follow the steps to confirm the release build hard-fails on missing .env.

## Important Notes

### Destructive Tests

- **04_rate_limits.sh** consumes 5 of the 24-hour ticket creation quota (plus 1 bank-change request). After running, the test investor will be rate-limited for the next 24 hours.
- **04_rate_limits.sh** creates a pending `bank_change_request` row. Manually delete this row in Supabase Studio if you need to re-run the test before the 7-day cooldown expires.

### Manual Verification Tests

- **06_xss_injection.sh** requires you to:
  1. Check the Supabase `support_tickets` table to confirm the payload is stored as literal text.
  2. Check the ops email to confirm it shows escaped HTML.
  3. Open the ticket in the Flutter app to confirm plain-text rendering (no JavaScript execution).

- **08_demo_bypass.sh** requires you to build, install, and manually test the release APK.

### Logging

Each test logs failures to `/tmp/r` (cURL response body). If a test fails, check the file:
```bash
cat /tmp/r
```

## Expected Behavior

All tests should complete with `PASS`. If any test shows `FAIL`:

1. Note which test failed.
2. Read the error message and the response in `/tmp/r`.
3. Check the security audit findings and Stream G plan for context.
4. Do NOT cut over to production until all tests pass.

## Cleanup

After testing, consider:
- Deleting the test investor account (`auth.users` row) in Studio to clean up the database.
- Rotating `REAL_INVESTOR_JWT` and `ANON_KEY` in `setup.sh` if credentials are compromised.

## Timing

The red-team suite should be run:
1. **During development** (Stream G.T1 — write only): Scripts are written but not executed.
2. **Before cutover** (Stream H.T1): Run the full suite on the production Supabase project to verify security gates hold.
3. **Post-launch monitoring**: Re-run periodically as part of security audits.
