# Project Status — arl_app

**Last updated:** 2026-05-13
**Current phase:** Implement
**Progress:** e2e_test_plan_v2_extended (2026-05-13) feature gaps — three "build now" groups landed: soft-delete sync (FG-02/03/04), document tiering (FG-05), and notification triggers (FG-06). Migrations 030–034 staged for orchestrator apply via Supabase MCP. Flutter Feature Audit fixes from 2026-05-12 also still applied.

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

## 2026-05-13 — e2e feature gaps (this branch)
- Group 1 — Soft-delete sync (FG-02/03/04): migrations `030_soft_delete_columns.sql` + `031_soft_delete_rls.sql`, webhook delete handlers, repo `deleted_at` filters, decision file, commit `03ec4f6`.
- Group 2 — Document tiering (FG-05): migrations `032_documents_tiering_schema.sql` + `033_documents_tiering_rls.sql`, DocumentsScreen Common/Project/Investor sections, demo data per tier, ops doc Part 7, decision file, commit `b00c9c4`.
- Group 3 — Notification triggers (FG-06): migration `034_notification_triggers.sql` (kyc / exit / ticket-reply / bank-change), CHECK constraint expansion, decision file, commit `77380c9`.
- Ops doc Part 8 (soft-delete) + Part 9 (notification triggers) appended in final pass.
- `flutter pub get` + `dart analyze lib` both clean.
- Migrations NOT applied locally — orchestrator applies via Supabase MCP.

## Blockers
- None.
