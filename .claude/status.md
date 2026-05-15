# Project Status — arl_app

**Last updated:** 2026-05-15
**Current phase:** Implement
**Progress:** Ops-doc consolidation done. 4 new topic deep-dives under docs/ops/ (~3,100 lines), Part 10 added to docs/ops_admin_guide.md as master TOC. Migration 045 applied LIVE on oynfhdqizebvgmaoiuax (fixes DEF-MKT-03 + DEF-OPS-2). 18 new defects logged in tracker (DEF-2026-05-15-01..18); LR-OPS-001 + LR-DB-045 marked Done. Three deferred items flagged for engineering review (auto-balance race vs Zoho webhook, documents storage_path RLS drift, units_available negative outlier).

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
- Extended E2E defect sweep (2026-05-13):
  - DEF-09 gallery-sync joins projects via `llps.zoho_llp_id` (commit be56f98).
  - DEF-10 migration 042 adds `investor_units.deleted_at` + amends owner SELECT RLS (commit bfda11e).
  - DEF-11 migration 043 adds `bank_change_requests.updated_at` to unblock 010 trigger and the 041 notification path (commit 9b79be9).
  - DEF-12 migration 044 enforces 5-year lock-in inside the `exit_requests` INSERT policy (commit 9ca6d80).

## Blockers
- None. Migrations 042-044 staged for user to apply via Supabase MCP.
