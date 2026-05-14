# Decision — Soft-delete sync from Zoho CRM

**Date:** 2026-05-13
**Status:** locked
**Scope:** FG-02, FG-03, FG-04 from e2e_test_plan_v2_extended_2026-05-13.md

## Problem
Today, when ops deletes a Contact or LLP record in Zoho CRM, the
zoho-crm-webhook has no delete branch. The mirrored Supabase row stays
queryable forever — a deleted investor still sees their app, a deleted
LLP still appears in marketplace listings. Hard-deleting from Supabase
would cascade through `investor_units`, `payouts`, `documents`,
`exit_requests`, etc. and destroy audit history.

## Decision
Soft-delete via a new `deleted_at TIMESTAMPTZ` column on each
CRM-mirrored table. RLS hides non-NULL rows from the app, the
zoho-crm-webhook stamps `deleted_at = now()` on delete-trigger
fire, and FK chains stay intact for ops + audit.

## What changed

### Schema (migration 030)
- `ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ` on `investors`,
  `llps`, `projects`.
- Partial index per table: `WHERE deleted_at IS NOT NULL`. Keeps the
  hot active-row indexes lean while making ops queries on the
  soft-deleted slice cheap.
- Column comments document the NULL = active contract.

### RLS (migration 031)
- `investors: read own row` → adds `AND deleted_at IS NULL`.
- `projects: visible to investors with units OR marketplace`
  → wraps existing predicate in `deleted_at IS NULL AND (...)`.
- `llps`: had no app-visible SELECT policy before. Enabled RLS and
  added a defensive policy that exposes a row only when the caller
  owns units in one of its active linked projects.
- `projects_public` view referenced in the e2e plan does NOT exist
  in this codebase — no migration creates it, no app code references
  it. Table-policy filtering is the source of truth; if/when the
  view is introduced, its underlying SELECT must filter
  `deleted_at IS NULL` to stay consistent.

### Edge function (zoho-crm-webhook)
- Dispatch checks `operation === 'delete'` first, then falls
  through to the existing upsert path.
- `handleContactDelete(supabase, data)`:
  - `UPDATE investors SET deleted_at = now() WHERE
    zoho_contact_id = $1 AND deleted_at IS NULL RETURNING id`.
  - For each returned id: `auth.admin.updateUserById(id,
    { ban_duration: '876000h' })`. GoTrue has no `banned: true`
    flag — `ban_duration` is the canonical knob. 100 years =
    indefinite.
- `handleLLPDelete(supabase, data)`:
  - `UPDATE llps SET deleted_at = now() WHERE
    zoho_llp_id = $1 AND deleted_at IS NULL RETURNING id`.
  - Cascade: `UPDATE projects SET deleted_at = now()
    WHERE llp_id IN (...) AND deleted_at IS NULL`.
- `event_type` in `webhook_log` already encodes `Contacts.delete` /
  `LLP_Creation_Module.delete` via the existing template, so the
  delete operation is auditable without schema change.

### App (defense in depth)
- `InvestorRepository.currentInvestor()`: added
  `.isFilter('deleted_at', null)`.
- `ProjectsRepository.myProjects() / marketplaceProjects() /
  projectById()`: same. RLS already enforces it; the explicit
  filter survives a stale-app build pointing at a DB where the
  policy regressed.

## Trade-offs
- `ban_duration: '876000h'` is a stringly-typed Supabase contract.
  Documented inline in the handler so future ops know how to
  un-ban (`ban_duration: 'none'`).
- The cascade from LLP → projects assumes the 1:1 webhook-default
  contract (one default project per LLP). Multi-project LLPs
  (admins create extras directly in Supabase) DO get cascaded —
  the `llp_id IN (...)` join keys it generically. Confirmed
  intentional.

## Open questions
- The e2e_test_plan referenced "migration 034 projects_public view"
  but no such view exists in current state. Migration numbers were
  off by ~3 in the source doc; numbered here as the next sequential
  030–034. Confirm with orchestrator before apply.

## Files
- supabase/migrations/20260513000000_030_soft_delete_columns.sql
- supabase/migrations/20260513010000_031_soft_delete_rls.sql
- supabase/functions/zoho-crm-webhook/index.ts
- lib/core/repositories/investor_repository.dart
- lib/core/repositories/projects_repository.dart
