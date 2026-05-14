# Privacy + Terms screens with consent flow

**Date:** 2026-05-13
**Status:** locked
**Phase:** Implement
**Migration:** 030 — `user_settings.terms_accepted_at`, `user_settings.privacy_accepted_at`

## Context
For private launch we need investors to (a) be able to read what data we
collect and how we use it, and (b) leave a record that they accepted both
documents at a known timestamp. Indian investors are covered by the DPDP
Act 2023, which expects an explicit consent moment plus a grievance
contact route. Until now the app shipped neither document and onboarding
proceeded without any acceptance gate.

## Decision

### Legal copy
- `lib/features/legal/legal_content.dart` holds the canonical text for
  both documents in `LegalDocs.privacyBody` / `LegalDocs.termsBody`,
  plus shared metadata (`effectiveDate`, `version`, `contactEmail`,
  `jurisdictionCity/State`, `entityName`, `brandName`,
  `templateBanner`).
- Both documents lead with a banner reading *"This document is a
  template. It has not yet been reviewed by independent legal counsel.
  Review with a qualified Indian lawyer before relying on it in a
  dispute."* The same banner is surfaced at the top of every render.

The Privacy Policy covers data we collect (identity, contact, bank,
investment, technical, auth), the legal basis (KYC/AML, contract,
consent), where it is stored (Supabase Postgres + Storage, Zoho CRM),
retention (8 years for financial records), security measures (TLS, hashed
PINs, RLS, masked fields), cookies/analytics (none), DPDP-Act rights
(access, correction, erasure, consent withdrawal, complaint to the Data
Protection Board), grievance officer contact, and revision notice.

The Terms of Service cover eligibility (Indian residents 18+, KYC
verified), account responsibilities, KYC as a precondition,
agri-investment risk disclosure (no guaranteed returns, principal at
risk, not investment/legal/tax advice), regulatory disclaimer, investor
duties, prohibited use, IP licence, termination, limitation of
liability capped at 12 months of management fees, indemnification,
dispute resolution under Indian law with Bangalore / Karnataka as the
exclusive-jurisdiction placeholder, severability, amendment notice, and
contact.

### Screens
- `lib/features/legal/legal_document_screen.dart`:
  - `LegalDocumentScreen` — shared layout with a back-affordance,
    template banner, and a scrollable card containing
    `SelectableText` of the body.
  - `PrivacyPolicyScreen` + `TermsScreen` are thin wrappers over the
    shared layout.
- New routes `RouteNames.privacy` (`/legal/privacy`) and
  `RouteNames.terms` (`/legal/terms`). Both are added to the
  `_publicRoutes` set so unauthenticated users can read them from the
  setup wizard. Both are top-level (no bottom-nav shell).

### Consent flow
- `InitialSetupScreen` adds a `_consentChecked` flag (default `false`).
- The bank step (final step) renders a `_ConsentBlock` with a checkbox
  and an `"I agree to the Terms of Service and Privacy Policy"` label
  whose two link spans push the respective screens.
- `_next` blocks the submit at step 3 unless `_consentChecked` is
  true and shows a `SnackBar` ("Accept the Terms and Privacy Policy to
  continue").
- After the investor row upsert succeeds, `_submit` calls
  `UserSettingsRepository.recordLegalConsent()` which upserts
  `user_settings.terms_accepted_at` and `user_settings.privacy_accepted_at`
  to `now()`. The consent write is wrapped in a try/catch — a failure
  there does not abort onboarding (investor row remains the source of
  truth for completion).

### Profile footer
- A new `_LegalLinkButton` row at the bottom of `ProfileScreen` exposes
  both documents post-auth: *"Privacy Policy · Terms of Service"*.

### Migration 030
```
alter table public.user_settings
  add column if not exists terms_accepted_at   timestamptz,
  add column if not exists privacy_accepted_at timestamptz;
```
Both columns are nullable — existing rows from migration 026 have no
back-fill. A future banner can re-prompt rows whose timestamps are NULL
or older than the active `LegalDocs.effectiveDate`.

RLS already restricts `user_settings` to `user_id = auth.uid()` from
migration 026; no policy change needed.

## Apply migration

```
supabase db query --linked --file supabase/migrations/20260513000000_030_legal_consent.sql
```
Or, if you prefer the canonical apply path:
```
supabase db push --linked
```
(Pushes any not-yet-applied migrations in `supabase/migrations/`.)

## Updating the legal copy
- All text + metadata is in `lib/features/legal/legal_content.dart`.
- When the copy is materially revised, bump
  `LegalDocs.effectiveDate` *and* `LegalDocs.version`. A future task
  can compare `user_settings.terms_accepted_at` against a database
  config row or a `LegalDocs.effectiveDate` shipped in the binary; if
  the stored timestamp is older, show a re-acceptance banner that
  re-runs `recordLegalConsent()` on click.

## Verification
- `dart analyze lib` — no issues.
- Routes reachable from setup wizard (pre-auth) + profile footer
  (post-auth).
- Submit button on setup blocks until checkbox is ticked.

## Follow-ups (out of scope)
- Re-consent banner when copy is revised.
- Counsel review of the template wording — see template banner.
- Confirm or change the Bangalore / Karnataka jurisdiction placeholder.
