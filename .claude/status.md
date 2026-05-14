# Project Status — arl_app

**Last updated:** 2026-05-13
**Current phase:** Implement
**Progress:** Pre-launch security hardening pass — 4 High audit findings fixed (S-002 coord leak via `projects_public` view, S-003 `sync_status` SECURITY INVOKER, S-004 anon CRUD revoke on post-019 tables, S-005 edge function CORS allow-list). Migrations 034/035/036 written; CORS helper centralised; 5 edge functions repointed. Apply + redeploy pending operator action — see `docs/security_audit_2026-05-13.md` apply checklist. `dart analyze lib` clean.

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
- 2026-05-13 — security hardening pass (4 High fixes, S-002..S-005). Audit doc + 4 decision files written; Part 7 (Security & CORS) appended to ops doc. Operator action still pending: `supabase db push` to apply migrations 034/035/036; `supabase secrets set APP_ALLOWED_ORIGINS=…`; `supabase functions deploy` on each of the 5 affected functions.

## Blockers
- None.
