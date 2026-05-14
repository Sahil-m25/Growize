# Project Status — arl_app

**Last updated:** 2026-05-13
**Current phase:** Implement
**Progress:** Sentry reintegrated with privacy-safe config (EU region, client-side PII scrubber, screenshots/view-hierarchy off, compile-time DSN). Critical user-action submit paths now report exceptions. Dev-only Test Crash tile on Profile screen. Flutter Feature Audit fixes — all 5 priorities complete from 2026-05-12.

## Summary
Flutter port of `Growize App Design.html` (17 pages). Core screens scaffolded across 12 features. Active work: HTML-parity fixes — global header/logo, font bundling, back-nav stack behavior.

## Completed Phases
- Ideate (design source-of-truth identified)
- Plan (HTML parity audit — see decisions/2026-04-24_html-parity-gap.md)

## Current Phase Details
- HTML-parity fixes: logo asset wiring, pubspec assets/fonts declaration, global sticky header, back-button stack restoration.
- Defensive back buttons added on support/project_detail screens (Apr 24).
- SecurityScreen rewritten to persist toggles + app-PIN (hashed client-side) + real login history; migration 026 applied via `supabase db query --linked` (see decisions/2026-05-12_security-screen-persistence.md).
- BiometricScreen registered as `/biometric`; used as enrollment gate from SecurityScreen Biometric Login toggle (see decisions/2026-05-12_biometric-screen-wiring.md).
- InitialSetupScreen now validates + persists KYC to `investors` (RLS scoped to own row); migration 027 applied (see decisions/2026-05-12_initial-setup-persistence.md).
- ExploreScreen "Request Consultation" persists to `consultation_requests` with 24h client-side dedup; migration 028 applied (see decisions/2026-05-12_explore-consultation-persistence.md).
- ExitScreen "Request Exit" persists to `exit_requests`, DB-level partial unique index guards duplicates, screen flips to submitted-state card; migration 029 applied (see decisions/2026-05-12_exit-requests-persistence.md).
- Ops doc inventory done — recommend appending SecurityScreen/BiometricScreen behaviour notes to `docs/ops_admin_guide.md` (canonical 1070-line ops doc); pending user decision.
- Sentry reintegrated (2026-05-13). DSN read via `--dart-define-from-file=.env.production` at build time; empty DSN skips init. Client-side `beforeSend` PII scrubber covers PAN, Aadhaar, IFSC, +91 phone, email local-part, JWT, Bearer, generic digit runs. Screenshots and view-hierarchy disabled. Critical paths instrumented: setup KYC submit, exit submit, consultation submit, sign-in (password/OTP/verify). Dev-only Test Crash tile on Profile. Ops doc Part 7 documents the runbook. See decisions/2026-05-13_sentry-reintegration.md.

## Blockers
- None.
