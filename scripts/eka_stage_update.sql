-- ============================================================
-- EKA LLP — stage seed + stage advance
--
-- Run AFTER applying:
--   supabase/migrations/20260822000000_066_phase_update_notifications.sql
--
-- ------------------------------------------------------------
-- VERIFIED AGAINST PRODUCTION 2026-08-22
--   project ref oynfhdqizebvgmaoiuax ("Growize Main DB", Postgres 17.6)
--
--   projects.id            6cb9fe7c-b173-4e39-a613-93bda03ca9f4
--   projects.name          EKA LLP
--   projects.status        Open for Reservation
--   total_units 22 / units_issued 2 / launch_year 2026-06-12
--   llps.zoho_llp_id       1169101000001929260
--   investor_units         2 rows, 2 distinct investors,
--                          allocation_status 'Issued', none soft-deleted
--   user_settings          0 rows org-wide -> nobody has opted out
--   project_phases         0 rows
--
--   >>> BLAST RADIUS: 2 investors. <<<
--
-- Schema notes that this script depends on — these differ from what
-- the repo's archived migrations suggest, so do not "simplify" them:
--   * `projects` has NO zoho_llp_id column. The Zoho id lives on
--     `llps.zoho_llp_id`; `projects.llp_id` -> `llps.id`.
--   * `project_phases` has NO started_at / completed_at columns in
--     prod (archived migration 053 was never applied there). This
--     script uses `phase_date` only.
--   * `investor_units` is soft-deleted via `deleted_at`.
--
-- Zoho carries no Phase_1..Phase_10 fields on LLP_Creation_Module and
-- no sync handler exists, so stage rows are seeded here rather than
-- synced. Steps 1-3 are READ ONLY. Nothing notifies until STEP 5.
-- ============================================================


-- ============================================================
-- STEP 0 — set the target stage. EDIT THIS.
-- ============================================================
-- Stage taxonomy (must match _fullLabels in
-- lib/features/projects/widgets/phase_timeline_6.dart):
--   0 Land Closed                     5 Water Source & Storage Ready
--   1 Design & Plan Locked            6 Power Ready
--   2 Site Prep                       7 Greenhouse
--   3 Core Civil                      8 Production Systems Installed
--   4 Procurement Locked              9 Compliance Closed + Go-live
--
-- Stages BEFORE this one are marked done; stages after stay pending.
\set target_stage 1


-- ============================================================
-- STEP 1 — READ ONLY. Confirm the project row.
-- ============================================================
SELECT p.id, p.name, p.status, p.launch_year, l.zoho_llp_id
FROM public.projects p
JOIN public.llps l ON l.id = p.llp_id
WHERE l.zoho_llp_id = '1169101000001929260'
  AND p.deleted_at IS NULL;
-- Expect exactly one row, id 6cb9fe7c-b173-4e39-a613-93bda03ca9f4.
-- If zero rows: the Zoho -> Supabase sync has not created it. STOP.


-- ============================================================
-- STEP 2 — READ ONLY. Existing phase rows (expect zero on first run).
-- ============================================================
SELECT ph.sort_order, ph.phase_name, ph.status, ph.phase_date
FROM public.project_phases ph
JOIN public.projects p ON p.id = ph.project_id
JOIN public.llps    l ON l.id = p.llp_id
WHERE l.zoho_llp_id = '1169101000001929260'
ORDER BY ph.sort_order;


-- ============================================================
-- STEP 3 — READ ONLY. DRY RUN: exactly who gets notified.
--
-- Mirrors the WHERE clause inside notify_project_phase_change()
-- one-for-one. The row count here IS your blast radius.
-- ============================================================
SELECT i.arl_id,
       i.name,
       COALESCE(us.notifications_enabled, TRUE) AS will_notify
FROM public.investor_units iu
JOIN public.projects  p ON p.id = iu.project_id
JOIN public.llps      l ON l.id = p.llp_id
JOIN public.investors i ON i.id = iu.investor_id
LEFT JOIN public.user_settings us ON us.user_id = iu.investor_id
WHERE l.zoho_llp_id = '1169101000001929260'
  AND iu.deleted_at IS NULL
  AND p.deleted_at IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.investor_id = iu.investor_id
      AND n.type = 'phase_update'
      AND n.metadata ->> 'project_id'  = p.id::TEXT
      AND n.metadata ->> 'stage_index' = (:target_stage)::TEXT
  )
ORDER BY i.arl_id;


-- ============================================================
-- STEP 4 — WRITES, BUT NOTIFIES NOBODY.
--
-- Seeds the 10 stage rows as `done` or `pending` — never `current` —
-- so the migration-066 trigger stays silent. Lets you seed history and
-- eyeball the timeline before anything reaches an investor.
--
-- Idempotent: re-running only fills gaps and corrects drift.
-- ============================================================
BEGIN;

WITH prj AS (
  SELECT p.id
  FROM public.projects p
  JOIN public.llps l ON l.id = p.llp_id
  WHERE l.zoho_llp_id = '1169101000001929260'
    AND p.deleted_at IS NULL
  LIMIT 1
),
taxonomy(sort_order, phase_name) AS (
  VALUES
    (0, 'Land Closed'),
    (1, 'Design & Plan Locked'),
    (2, 'Site Prep'),
    (3, 'Core Civil'),
    (4, 'Procurement Locked'),
    (5, 'Water Source & Storage Ready'),
    (6, 'Power Ready'),
    (7, 'Greenhouse'),
    (8, 'Production Systems Installed'),
    (9, 'Compliance Closed + Go-live')
)
INSERT INTO public.project_phases (project_id, phase_name, status, sort_order)
SELECT prj.id,
       t.phase_name,
       CASE WHEN t.sort_order < (:target_stage) THEN 'done' ELSE 'pending' END,
       t.sort_order
FROM prj
CROSS JOIN taxonomy t
WHERE NOT EXISTS (
  SELECT 1 FROM public.project_phases ph
  WHERE ph.project_id = prj.id AND ph.sort_order = t.sort_order
);

-- Correct drift on rows that already existed. The target stage is
-- deliberately left alone here — STEP 5 owns it.
UPDATE public.project_phases ph
SET status = CASE WHEN ph.sort_order < (:target_stage) THEN 'done' ELSE 'pending' END
FROM public.projects p
JOIN public.llps l ON l.id = p.llp_id
WHERE p.id = ph.project_id
  AND l.zoho_llp_id = '1169101000001929260'
  AND ph.sort_order <> (:target_stage)
  AND ph.status IS DISTINCT FROM
      CASE WHEN ph.sort_order < (:target_stage) THEN 'done' ELSE 'pending' END;

-- Inspect before committing.
SELECT ph.sort_order, ph.phase_name, ph.status
FROM public.project_phases ph
JOIN public.projects p ON p.id = ph.project_id
JOIN public.llps    l ON l.id = p.llp_id
WHERE l.zoho_llp_id = '1169101000001929260'
ORDER BY ph.sort_order;

COMMIT;
-- ^ change to ROLLBACK; if the listing looks wrong.


-- ============================================================
-- STEP 5 — THE NOTIFYING STEP. This one reaches users.
--
-- Flipping the target row to `current` fires
-- trg_notify_project_phase_change, inserting one `phase_update`
-- notification per investor listed in STEP 3.
--
-- Investors see it in the bell / Activity feed the NEXT TIME THEY OPEN
-- THE APP. There is no push transport and no realtime subscription on
-- notifications — see
-- docs/plans/2026-08-22_push_notifications_fcm_scope.md.
-- ============================================================
BEGIN;

UPDATE public.project_phases ph
SET status     = 'current',
    phase_date = COALESCE(ph.phase_date, CURRENT_DATE)
FROM public.projects p
JOIN public.llps l ON l.id = p.llp_id
WHERE p.id = ph.project_id
  AND l.zoho_llp_id = '1169101000001929260'
  AND ph.sort_order = (:target_stage)
  AND ph.status IS DISTINCT FROM 'current';

-- Verify the fan-out before committing. Expect investors = 2.
SELECT n.title, n.body, n.metadata ->> 'stage_index' AS stage,
       COUNT(*) AS investors
FROM public.notifications n
JOIN public.projects p ON p.id::TEXT = n.metadata ->> 'project_id'
JOIN public.llps    l ON l.id = p.llp_id
WHERE l.zoho_llp_id = '1169101000001929260'
  AND n.type = 'phase_update'
GROUP BY 1, 2, 3;

COMMIT;
-- ^ ROLLBACK; here un-sends the notifications, as long as you have not
--   committed. After COMMIT, use the undo block below.


-- ============================================================
-- UNDO (after commit) — retract the notifications for one stage.
-- Does not reset the phase row; do that separately if needed.
-- ============================================================
-- DELETE FROM public.notifications n
-- USING public.projects p
-- JOIN public.llps l ON l.id = p.llp_id
-- WHERE n.type = 'phase_update'
--   AND l.zoho_llp_id = '1169101000001929260'
--   AND n.metadata ->> 'project_id'  = p.id::TEXT
--   AND n.metadata ->> 'stage_index' = '1';   -- the stage you sent
