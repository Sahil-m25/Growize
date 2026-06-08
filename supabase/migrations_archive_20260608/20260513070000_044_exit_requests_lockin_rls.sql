-- ============================================================
-- 044: Enforce 5-year lock-in server-side on exit_requests (DEF-12)
-- ============================================================
-- Migration 029 created exit_requests with
--   WITH CHECK (user_id = (SELECT auth.uid()))
-- which authorises the row but does not enforce the product rule
-- that an investor can only request an exit five years after the
-- allocation's investment_date. The Flutter UI gates the action
-- client-side, but a direct PostgREST POST bypasses that.
--
-- Investment date column on investor_units is `investment_date`
-- (DATE) per migration 003 — sourced from Zoho's Investment_Date.
-- ============================================================

DROP POLICY IF EXISTS "exit_requests: insert own" ON public.exit_requests;

CREATE POLICY "exit_requests: insert own"
  ON public.exit_requests FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = (SELECT auth.uid())
    AND EXISTS (
      SELECT 1
        FROM public.investor_units iu
       WHERE iu.id = investor_unit_id
         AND iu.investor_id = (SELECT auth.uid())
         AND iu.investment_date IS NOT NULL
         AND iu.investment_date + INTERVAL '5 years' <= NOW()
    )
  );

COMMENT ON POLICY "exit_requests: insert own" ON public.exit_requests IS
  'Owner can only insert an exit request once the allocation has cleared the 5-year lock-in. Enforced server-side; the Flutter UI gate is defence-in-depth.';
