# InitialSetupScreen — persist KYC on submit

**Date:** 2026-05-12
**Phase:** Implement
**Status:** locked

## Problem
Audit row `InitialSetupScreen (setup_screen.dart)` in
`ARL_Test_Tracker.xlsx` sheet `Flutter Feature Audit` was Partial. The
3-step wizard collected name/email/DOB → PAN/Aadhaar → bank, then the
final "Submit for Verification" button only flashed a snackbar and
routed home. Nothing was persisted, no validation gated submit.

## Decision
- Add a `Form` per step with field-level validators + inline error
  messages (`AutovalidateMode.onUserInteraction`).
  - PAN: `^[A-Z]{5}[0-9]{4}[A-Z]$` (auto-uppercased)
  - Aadhaar: exactly 12 digits
  - IFSC: `^[A-Z]{4}0[A-Z0-9]{6}$`
  - Account: 9–18 digits
  - DOB: `DD-MM-YYYY`, not in the future
  - Email: standard regex; pre-filled from `auth.currentUser.email`
- On final submit, `InvestorRepository.upsertOnboarding(...)` writes to
  `public.investors` with `id = auth.uid()`. Only **masked** projections
  of PAN / Aadhaar / account are persisted — full numbers never reach
  the DB (matches the existing `pan_masked` / `aadhaar_masked` /
  `bank_account_masked` schema and the bank-change-request masking
  pattern). `kyc_status` set to `'pending'`; ARL ops moves it forward.
- Success → `currentInvestorProvider` invalidated, snackbar, `go(home)`.

### Migration 027 (applied)
The existing `investors` table only granted `SELECT` to authenticated
users; writes were edge-function / service-role only. To let a fresh
auth user persist their own onboarding from the client:
- `ALTER TABLE public.investors ALTER COLUMN arl_id DROP NOT NULL`
  (self-onboarded rows don't get an ARL contact ID until staff assigns
  one; Zoho-synced rows keep theirs.)
- `CREATE POLICY "investors: insert own row" ... WITH CHECK (id = auth.uid())`
- `CREATE POLICY "investors: update own row" ... USING/CHECK (id = auth.uid())`
- `GRANT INSERT, UPDATE ON public.investors TO authenticated`

Applied via `supabase db query --linked -f ...027*.sql`. Verified post-
apply: `arl_id is_nullable=YES`, 3 policies present (SELECT/INSERT/
UPDATE), `authenticated` grantee now has SELECT/INSERT/UPDATE.

## Why mask client-side (and not Edge Function)
The existing onboard-investor Edge Function is staff-invite only
(`X-ARL-Admin-Secret` gate) and doesn't accept KYC fields. Building a
new public-callable function to take raw PAN/Aadhaar and mask
server-side would put plaintext on the wire and in logs. Masking on
device and persisting only the tail keeps the raw IDs off Supabase
entirely — RLS-scoped UPDATE is the right place for this write.

## Touched files
- `supabase/migrations/20260512010000_027_investors_self_onboard.sql` (new, applied)
- `lib/core/repositories/investor_repository.dart` (+`upsertOnboarding`)
- `lib/features/auth/setup_screen.dart` (Form + validators + submit; ConsumerStatefulWidget)

## Verification
- `flutter pub get` — Got dependencies!
- `dart analyze lib` — `No issues found!`
- DB introspection after migration: nullability + policies + grants confirmed.
- Real device walkthrough deferred to UAT.

## Rollback
- `DROP POLICY "investors: insert own row" ON public.investors;`
- `DROP POLICY "investors: update own row" ON public.investors;`
- `REVOKE INSERT, UPDATE ON public.investors FROM authenticated;`
- `ALTER TABLE public.investors ALTER COLUMN arl_id SET NOT NULL;`
- Revert files listed above.
