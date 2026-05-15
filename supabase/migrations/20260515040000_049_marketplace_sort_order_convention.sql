-- ============================================================
-- MIGRATION 049 — marketplace_sort_order: document a convention,
-- backfill the zeros.
--
-- Resolves: DEF-2026-05-15-15 (DEF-MKT-04).
--
-- 6 of 8 listed projects had sort_order = 0 because no default
-- value existed and no Zoho field maps to the column. Without a
-- convention the marketplace order is effectively random for the
-- zeros, and ops cannot "insert above" without renumbering.
--
-- Convention (documented as a column COMMENT for future ops):
--   * Default value: 100.
--   * Lower number = earlier in the marketplace.
--   * Increments of 10 (100, 110, 120, …) so a new listing can
--     slot between two existing ones without renumbering.
--   * 0 is reserved for "explicitly hidden in sort order" (no
--     such row today; behaviour is equivalent to 100 in the UI).
-- ============================================================

ALTER TABLE public.projects
  ALTER COLUMN marketplace_sort_order SET DEFAULT 100;

UPDATE public.projects
   SET marketplace_sort_order = 100
 WHERE marketplace_sort_order = 0
   AND deleted_at IS NULL;

COMMENT ON COLUMN public.projects.marketplace_sort_order IS
  'Lower = earlier in marketplace. Default 100; use multiples of '
  '10 (100, 110, 120, …) so a new listing can slot between two '
  'existing ones without renumbering. Convention added 2026-05-15.';

-- Rollback:
--   ALTER TABLE public.projects ALTER COLUMN marketplace_sort_order DROP DEFAULT;
--   -- Values are not auto-restored; restore from snapshot if required.
