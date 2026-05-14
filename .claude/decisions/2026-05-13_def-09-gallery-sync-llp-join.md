# DEF-09 — gallery-sync joins projects via llps.zoho_llp_id

**Date:** 2026-05-13
**Phase:** Implement
**Status:** locked
**Commit:** be56f98

## Problem
`supabase/functions/gallery-sync/index.ts:107` selected
`projects.zoho_llp_id` and filtered `not("zoho_llp_id", "is", null)`.
After the LLP/project schema split on cloud, that column no longer
lives on `projects` — `projects.llp_id` is the FK and `llps.zoho_llp_id`
holds the Zoho identifier. Every cron run failed at the first query
with "column projects.zoho_llp_id does not exist".

## Decision
Use a PostgREST embedded relation on the existing query so the
function gets the Zoho id through the FK without a second round-trip:

```ts
.select("id, name, llp_status, llp:llps!inner(zoho_llp_id)")
.neq("llp_status", "completed")
.not("llp_id", "is", null);
```

Inside the per-project loop, normalise the embedded relation (object
or array depending on cardinality) into a single `zohoLlpId` and skip
projects where it is missing. The three downstream URL builds
(`/Attachments`, `/Attachments/<id>`) and the warning log now use that
local variable instead of `project.zoho_llp_id`.

## Touched files
- `supabase/functions/gallery-sync/index.ts`

## Verification
- File hand-reviewed — no remaining `project.zoho_llp_id` references.
- `dart analyze lib` — clean (TS-only change).
- Deploy intentionally deferred — user applies via Supabase MCP.

## Rollback
- `git revert be56f98`.
