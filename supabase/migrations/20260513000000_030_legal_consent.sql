-- Migration 030 — record consent timestamps for Privacy Policy + Terms of Service.
--
-- Driver: launch-readiness pass (2026-05-13). The app now blocks the
-- onboarding submit until the user ticks an "I agree to Terms + Privacy"
-- checkbox. We persist the moment of acceptance per user so that, if the
-- legal copy is revised, we can compare against the active document's
-- effective date to decide whether a re-consent prompt is required.
--
-- Both columns are nullable: a row may exist (PIN / biometric toggles set)
-- before the user has gone through the consent gate, and a returning user
-- whose acceptance pre-dates this migration will simply have NULLs (no
-- back-fill — they get re-prompted on next sign-in if we surface a banner).
--
-- RLS already restricts user_settings rows to `user_id = auth.uid()` from
-- migration 026; no policy change needed.

alter table public.user_settings
  add column if not exists terms_accepted_at   timestamptz,
  add column if not exists privacy_accepted_at timestamptz;

comment on column public.user_settings.terms_accepted_at is
  'Timestamp at which the user accepted the active Terms of Service. NULL = never accepted.';
comment on column public.user_settings.privacy_accepted_at is
  'Timestamp at which the user accepted the active Privacy Policy. NULL = never accepted.';
