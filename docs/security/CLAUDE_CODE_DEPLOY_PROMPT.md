You have access to the Supabase MCP, the Postgres best-practices MCP, the
Playwright MCP, and the Zoho CRM MCP. The repo at
C:\Users\Sahil\Downloads\ARL\arl_app has 3 security-fix PRs already
implemented in git worktrees, with Deno integration tests passing
locally (no live deploy yet). The full remediation plan is at
docs/security/REMEDIATION_PLAN_AGENT_E.md.

WORK IS ALREADY DONE IN THESE WORKTREES (do not re-implement):

  PR-A: .claude/worktrees/pr-a-bank-change        fix/bank-change-validation-kyc-gate
         19/19 integration tests pass — bank-change-request now enforces
         RBI IFSC regex, length caps (bank_name 80, ifsc 11,
         holder_name 100), and a kyc_status='verified' gate that runs
         before the cooldown lookup. Test at test/pr-a-integration.test.ts.

  PR-C: .claude/worktrees/pr-c-consultation-lookup  fix/notify-consultation-investor-lookup
         16/16 integration tests pass — notify-consultation-request now
         looks up investors by id (not the non-existent user_id column)
         and selects the right name (not full_name) so Slack posts
         show "Alice Investor <alice@x.in> +91-99999-00001" instead of
         "Unknown investor". Test at test/pr-c-integration.test.ts.

  PR-D: .claude/worktrees/pr-d-app-releases       feat/app-releases-channel
         29/29 integration tests pass — created the missing
         app_releases table (migration 064) and added a channel filter
         to latest-app-version so a web user no longer receives the
         android APK. Test at test/pr-d-integration.test.ts.

WHAT I NEED YOU TO DO — strictly in this order, STOP and report after
each step if it fails:

STEP 1: Apply migration 064 to staging.

   Use the Supabase MCP's `apply_migration` tool. The SQL is at:
   .claude/worktrees/pr-d-app-releases/supabase/migrations/20260613000000_064_app_releases.sql

   The migration creates the app_releases table, the unique index, the
   RLS policy, and inserts 3 v1 backfill rows. Read the file first so
   you know what's in it. Apply it to the project at
   oynfhdqizebvgmaoiuax (this is the dev/staging project — confirm with
   me if you're unsure which project ref to target).

   After applying, verify with:
     SELECT channel, version_code, version_name, apk_url, web_url
       FROM public.app_releases ORDER BY channel, version_code;
   Expected: 3 rows (android v1 with apk_url, ios v1 with apk_url,
   web v1 with web_url).

STEP 2: Deploy the 3 Edge Functions.

   Use the Supabase MCP's `deploy_edge_function` tool. Source paths
   (relative to repo root):
     - supabase/functions/bank-change-request/         (PR-A)
     - supabase/functions/notify-consultation-request/  (PR-C)
     - supabase/functions/latest-app-version/           (PR-D)

   For each, the function's main file is index.ts inside its folder.
   After deploying each, note the deployment URL the Supabase MCP
   returns (it should look like
   https://oynfhdqizebvgmaoiuax.supabase.co/functions/v1/<name>).

STEP 3: Live curl tests of the 3 functions.

   You need a real JWT for a test investor. Use the Supabase MCP to
   query:
     SELECT id, email, kyc_status FROM public.investors LIMIT 5;
   Pick one with kyc_status='verified' for the bank-change test, and
   one with kyc_status='pending' for the KYC-gate negative test.
   Use the Supabase MCP's `auth.admin.generateLink` (or similar) to
   mint a magic-link / session for that user, then extract the access
   token. If that flow is not available, ask me for a test JWT — do
   not invent one.

   For each function, fire the curl calls listed in
   docs/security/REMEDIATION_PLAN_AGENT_E.md under the "Manual verify
   after deploy" section of PR-A, PR-C, PR-D. Report the HTTP status
   of each call and whether it matches expected.

STEP 4: Browser-level smoke test with Playwright MCP.

   Use the playwright MCP to open a browser to the app's bank-change
   screen. The app is presumably at https://app.growize.in (or the
   staging equivalent — ask me if unsure). Log in as the same test
   investor you used in STEP 3. Navigate to Profile > Bank Details.
   Try to submit a bad IFSC (e.g. "BADCODE001") and verify the error
   toast appears. Try to submit a 200-character holder name and verify
   the server returns the "holder_name_too_long" error. Screenshot
   before/after for the report.

REPORT BACK with a per-step summary:
  - STEP 1: did the migration apply? Did the verification SELECT
    return 3 rows?
  - STEP 2: what deployment URL was returned for each function?
  - STEP 3: for each curl, what was the actual HTTP status vs
    expected? (Expected list is in the plan.)
  - STEP 4: did the browser-level smoke test pass? Screenshots
    embedded.

DO NOT push the branches to GitHub. I will do that after I see the
live verification report.

DO NOT modify any code in the worktrees. If a step fails, STOP and
report. Do not paper over it.

Use --max-turns 40 to keep this bounded.
