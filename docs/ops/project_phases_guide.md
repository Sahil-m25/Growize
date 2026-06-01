# Project Phases — Ops Guide

How project-phase timeline data flows (or rather, does **not** flow) into the
Growize backend, how to verify the current state, and how to fix wrong rows.

**Audience:** ARL ops (`tech@agresearchlabs.com`) working in Supabase Studio
against project `oynfhdqizebvgmaoiuax`.

**TL;DR up front (this is important):** Project phases are **not** synced from
Zoho. The `project_phases` table is **currently empty (0 rows across all 15
live projects)**. The app's project-detail timeline UI is therefore showing
**nothing** for every project. See "Known gotchas" §1 — this is most likely
what triggered the question.

---

## 1. Where phase data lives

### 1.1 Supabase: `public.project_phases`

Defined in migration `004_project_detail_phases_crops.sql`. The migration
header is explicit:

> "No Zoho module exists yet for these. Seeded manually via Supabase Studio
> by ARL staff. When a Zoho module is created later, zoho-crm-webhook can
> upsert into these tables using zoho_phase_id / zoho_crop_id — schema
> already has the column ready."

Schema (verified live):

| column          | type        | nullable | default              | notes |
|-----------------|-------------|----------|----------------------|-------|
| `id`            | uuid        | NO       | `gen_random_uuid()`  | PK |
| `project_id`    | uuid        | NO       | —                    | FK → `projects(id)` ON DELETE CASCADE |
| `zoho_phase_id` | text        | YES      | —                    | UNIQUE — reserved for a future Zoho module |
| `phase_name`    | text        | NO       | —                    | e.g. "Land Preparation", "Planting", "First Harvest" |
| `status`        | text        | NO       | `'pending'`          | CHECK IN (`'done'`, `'current'`, `'pending'`) |
| `phase_date`    | date        | YES      | —                    | Target / completion date |
| `sort_order`    | int         | NO       | `0`                  | Display ordering — lower first |
| `sub_items`     | jsonb       | NO       | `'[]'`               | Nested checklist `[{"label":"1.1","detail":"…","date":"…","done":true}]` |
| `updated_at`    | timestamptz | YES      | `now()`              | Maintained by `trg_project_phases_updated_at` |

Indexes:
- `project_phases_pkey` (id)
- `project_phases_zoho_phase_id_key` UNIQUE (zoho_phase_id)
- `idx_phases_project_order` (project_id, sort_order ASC)

Constraints:
- `project_phases_status_check` — status must be one of `done`, `current`, `pending`
- `project_phases_project_id_fkey` — ON DELETE CASCADE from `projects`

RLS — investors get read-only access to phases for their own projects:

```sql
-- Policy "project_phases: via investor units" (SELECT only)
USING (
  project_id IN (
    SELECT investor_units.project_id
    FROM investor_units
    WHERE investor_units.investor_id = (SELECT auth.uid())
  )
)
```

There is **no `INSERT`/`UPDATE`/`DELETE` policy** — ops writes via the
service-role from Supabase Studio. The mobile app cannot write phases.

### 1.2 `projects` table — no `current_phase` column

`public.projects` has 37 columns. None of them are named `phase`,
`current_phase`, `stage`, `milestone`, etc. Confirmed by:

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND column_name ILIKE '%phase%';
-- Only project_phases.phase_date, .phase_name, .zoho_phase_id
```

What `projects` does have that is sometimes confused for "phase":

- `projects.status` — text mirror of Zoho `LLP_Status`. Distinct values today:
  `Active`, `Darft` (sic — typo in the Zoho picklist), `Fully Subscribed / Closed`,
  `Open for Issuance`, `Open for Reservation`. This is the **LLP commercial
  lifecycle**, not the **operational farm-timeline phase**.

### 1.3 Zoho CRM source-of-truth — does not exist

LLP_Creation_Module has **no field whose api_name or label contains the word
"phase"** (verified by dumping all field metadata via `getFields` and
grepping). There is no `LLP_Phase`, `Current_Phase`, `Project_Phase`,
`Phase_Start_Date`, etc. on the module.

There is no Zoho module backing `project_phases` either. The `zoho_phase_id`
column was added in anticipation of a future module that hasn't been built.

---

## 2. How phase changes

### 2.1 Current state — nothing changes them

```
[Zoho LLP_Creation_Module] -- workflow CF --> [zoho-crm-webhook] --handleProject--> [llps + projects]
                                                                                     │
                                                                                     │ (no path)
                                                                                     ▼
                                                                              [project_phases]
                                                                              (manual seed only)
```

- `zoho-crm-webhook` (live version 31). `handleProject()` writes to `llps`
  and `projects` only. The string `project_phases` appears **twice** in the
  source — both inside comments about the ON DELETE CASCADE map, never in a
  write statement.
- `zoho-reconcile-daily` (live version 11, runs daily 01:00 UTC).
  Reconciles Contacts, LLP_Creation_Module, LLP_UnitAllocation_Module. Does
  **not** touch `project_phases`.
- No other edge function references the table. No trigger writes to it (only
  the `set_updated_at()` trigger fires on update, and no one updates).
- The Flutter app reads via `client.from('project_phases').select()` in
  `lib/core/repositories/projects_repository.dart::phasesFor()` and never
  writes.

**Net result: the only way a `project_phases` row exists is if an ARL ops
user inserts it manually via Supabase Studio (or service-role SQL).**

### 2.2 If you change something in Zoho

- Changing `LLP_Status` in Zoho will fire the existing LLP workflow → webhook
  → updates `projects.status`. It will **not** create or update any phase row.
- Adding a new "Project Phase" field in Zoho would do nothing until both the
  webhook and the reconcile job are extended to read it.

### 2.3 If you want phases to appear in the app

You must seed them manually. The schema is ready. Today, with zero rows,
the app's timeline UI is empty for all 15 projects. See §4 Path B for the
INSERT pattern.

---

## 3. How to verify

Run any of these in Supabase Studio (SQL editor) against project
`oynfhdqizebvgmaoiuax`. All are pure SELECTs.

### 3.1 Per-project audit — current phase, full history, freshness

```sql
SELECT
  p.id                                                AS project_id,
  p.name                                              AS project_name,
  p.status                                            AS llp_status,           -- NOT the phase
  current_ph.phase_name                               AS current_phase,
  current_ph.phase_date                               AS current_phase_date,
  COALESCE(history.phase_count, 0)                    AS total_phases,
  history.phases_ordered_by_date,
  MAX(ph.updated_at)                                  AS last_phase_update
FROM projects p
LEFT JOIN LATERAL (
  SELECT phase_name, phase_date
  FROM project_phases
  WHERE project_id = p.id AND status = 'current'
  ORDER BY sort_order
  LIMIT 1
) current_ph ON true
LEFT JOIN LATERAL (
  SELECT
    COUNT(*) AS phase_count,
    string_agg(
      phase_name || ' [' || status || ']' ||
      COALESCE(' @ ' || phase_date::text, ''),
      ' -> '
      ORDER BY COALESCE(phase_date, '1900-01-01'::date), sort_order
    ) AS phases_ordered_by_date
  FROM project_phases
  WHERE project_id = p.id
) history ON true
LEFT JOIN project_phases ph ON ph.project_id = p.id
WHERE p.deleted_at IS NULL
GROUP BY p.id, p.name, p.status, current_ph.phase_name, current_ph.phase_date,
         history.phase_count, history.phases_ordered_by_date
ORDER BY p.name;
```

### 3.2 Sanity checks (one-liners)

```sql
-- Row counts
SELECT COUNT(*) AS total_rows, COUNT(DISTINCT project_id) AS distinct_projects
FROM project_phases;

-- Projects with NO phase rows (today: all 15)
SELECT p.id, p.name, p.status
FROM projects p
LEFT JOIN project_phases ph ON ph.project_id = p.id
WHERE ph.id IS NULL AND p.deleted_at IS NULL
ORDER BY p.name;

-- Projects with MORE THAN ONE "current" phase (should be zero — UI shows
-- the first by sort_order, but two-current is a data smell)
SELECT project_id, COUNT(*) AS current_count
FROM project_phases
WHERE status = 'current'
GROUP BY project_id
HAVING COUNT(*) > 1;

-- Future-dated "done" phases (data smell — done in the future is impossible)
SELECT id, project_id, phase_name, phase_date, status
FROM project_phases
WHERE status = 'done' AND phase_date > CURRENT_DATE;

-- NULL or empty phase_name (NOT NULL but empty strings sneak through)
SELECT id, project_id, phase_name, status
FROM project_phases
WHERE phase_name IS NULL OR trim(phase_name) = '';

-- Orphan phase rows — should be impossible due to FK CASCADE, but check anyway
SELECT ph.id, ph.project_id
FROM project_phases ph
LEFT JOIN projects p ON p.id = ph.project_id
WHERE p.id IS NULL;

-- Phase rows pointing at soft-deleted projects
SELECT ph.id, ph.project_id, p.name, p.deleted_at
FROM project_phases ph
JOIN projects p ON p.id = ph.project_id
WHERE p.deleted_at IS NOT NULL;
```

### 3.3 What an investor sees vs. what ops sees

The Flutter app fetches via
`ProjectsRepository.phasesFor(projectId)` which calls
`from('project_phases').select().eq('project_id', projectId).order('sort_order')`.
Anything you see in §3.1 for a given project is exactly what that investor
sees, modulo RLS (investor must own units in the project).

---

## 4. How to rectify a wrong phase

### Path A — Preferred: fix it at the source

**Today this path does not exist.** There is no Zoho field that maps to
`project_phases`. If you change anything in Zoho, no phase row will move.

(If a Zoho module for phases is created later, the path will be: edit
record in Zoho → workflow CF fires → `zoho-crm-webhook` upserts. Re-read
this doc when that ships.)

### Path B — Direct SQL in Supabase Studio (the only path today)

Service-role writes from Studio bypass RLS. **Use carefully** — there is no
soft-delete on this table.

Before you change anything, snapshot the row:

```sql
SELECT * FROM project_phases WHERE id = '<phase-uuid>';
```

#### B.1 Mark a phase as "current" (move the milestone arrow)

The status check accepts only `done`, `current`, `pending`. The UI does not
enforce a single-current invariant, but ops should:

```sql
-- One transaction so the project never has zero or two "current" rows
BEGIN;

-- Demote everything currently "current" on this project to "done"
UPDATE project_phases
SET status = 'done'
WHERE project_id = '<project-uuid>' AND status = 'current';

-- Promote the new phase
UPDATE project_phases
SET status     = 'current',
    phase_date = CURRENT_DATE  -- or the real milestone date
WHERE id = '<phase-uuid>';

COMMIT;
```

#### B.2 Rename / re-date a phase

```sql
UPDATE project_phases
SET phase_name = 'Corrected name',
    phase_date = '2026-06-15'
WHERE id = '<phase-uuid>';
```

#### B.3 Seed phases for a project from scratch

```sql
INSERT INTO project_phases (project_id, phase_name, status, phase_date, sort_order, sub_items)
VALUES
  ('<project-uuid>', 'Land Preparation', 'done',    '2026-01-15', 1, '[]'),
  ('<project-uuid>', 'Planting',         'current', '2026-03-10', 2,
     '[{"label":"2.1","detail":"Saplings sourced","date":"2026-03-05","done":true},
       {"label":"2.2","detail":"Irrigation laid","date":"2026-03-09","done":true}]'::jsonb),
  ('<project-uuid>', 'First Harvest',    'pending', '2026-09-01', 3, '[]');
```

#### B.4 Delete a wrongly-inserted phase

```sql
DELETE FROM project_phases WHERE id = '<phase-uuid>';
```

#### Warnings

- **No restore.** This table has no `deleted_at` column. A `DELETE` is final;
  there is no soft-delete window.
- **No audit log.** Direct UPDATEs/DELETEs are not recorded anywhere (the
  `webhook_log` table only captures webhook traffic, not Studio writes).
- **No Zoho clobber risk today.** Because no sync job writes here, your
  manual edits will not be overwritten — unlike `projects` or `investors`,
  where the reconcile cron would undo Studio edits on the next run. **If a
  Zoho phases module is added later, this stops being true.**

---

## 5. Known gotchas / data inconsistencies found in this audit

1. **`project_phases` is empty for every project (15 / 15).**
   All 15 live projects have zero rows in `project_phases`. The project-detail
   timeline UI in the app is therefore empty for every investor. The seed
   data that migration 004 expects ARL staff to insert was never written.
   *Defect: DEF-V31-PHASE-001.*

2. **No automated sync path.** Both `zoho-crm-webhook` and
   `zoho-reconcile-daily` ignore phases. The `zoho_phase_id` column is a
   placeholder for a future module that does not exist in Zoho. There is no
   workflow rule, custom function, or scheduled job that ever writes a phase
   row. *Defect: DEF-V31-PHASE-002.*

3. **`projects.status` is NOT a phase.** It mirrors Zoho `LLP_Status`
   (commercial states like `Open for Reservation`, `Active`, `Fully
   Subscribed / Closed`). It is easy to confuse with "phase" because both
   sound like lifecycle markers. The app uses `status` for the marketplace
   gate (`is_listed_in_marketplace` is derived from it) and uses
   `project_phases` for the timeline UI — they are unrelated.

4. **Zoho picklist typo leaks into Supabase.** `projects.status` contains
   the value `Darft` (one project: "Gamma Empty LLP-demo"). This is the
   Zoho picklist label, not a Supabase bug — the webhook copies the string
   verbatim. *Defect: DEF-V31-PHASE-003* (low severity; fix in Zoho admin).

5. **No single-`current` invariant.** Nothing in the schema or app prevents
   two `status='current'` rows for the same project. Use the §3.2 query to
   spot-check. *Defect: DEF-V31-PHASE-004* (latent; not breached today
   because the table is empty).

6. **No INSERT/UPDATE policy.** RLS allows investor SELECT only. All writes
   go through service-role (Studio). If an ARL staff webapp ever needs
   ops users to edit phases without Studio, an RLS policy will need to be
   added.

7. **Hard delete only.** `ON DELETE CASCADE` from `projects` will wipe all
   phase rows the moment a project is hard-deleted (e.g. by the Zoho LLP
   delete webhook). There is no recovery. If you ever populate phases,
   consider a periodic SQL dump.

---

## 6. Quick reference

| Question | Answer |
|----------|--------|
| Where do phases live? | `public.project_phases` in Supabase |
| Who writes them? | ARL ops, manually, via Supabase Studio |
| Does Zoho push phases? | No, not today |
| Does the reconcile cron pull phases? | No |
| Can investors edit phases? | No — read-only via RLS |
| What's the "current" phase? | The row with `status='current'` (lowest `sort_order` if multiple) |
| How do I find wrong rows? | §3 audit SQL |
| How do I fix a wrong row? | §4 Path B (direct SQL) |
| Will my fix get overwritten? | Not today. Yes, if a Zoho phase module is added later. |
