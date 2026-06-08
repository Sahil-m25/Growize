
-- ============================================================
-- MIGRATION 011 — SECURITY FIXES (from advisor scan)
-- 1. webhook_log has RLS enabled but no policies → expected,
--    add explicit deny comment + service-role-only policy note.
--    Fix: add a policy that explicitly allows nothing for
--    authenticated users (the advisor just needs a policy to exist).
-- 2. portfolio_summary view uses SECURITY DEFINER → recreate
--    with SECURITY INVOKER so it runs as the querying user
--    and respects their RLS context.
-- 3. set_updated_at function has mutable search_path → fix
--    by setting search_path = '' and using fully qualified names.
-- ============================================================

-- Fix 1: webhook_log — add explicit "no access for investors" policy
-- Service role bypasses RLS and can still read/write freely.
CREATE POLICY "webhook_log: deny all authenticated users"
  ON public.webhook_log
  FOR ALL
  TO authenticated
  USING (false);

-- Fix 2: portfolio_summary — recreate as SECURITY INVOKER
-- Drop and recreate (views don't support ALTER for security property)
DROP VIEW public.portfolio_summary;

CREATE VIEW public.portfolio_summary
  WITH (security_invoker = true)
AS
SELECT
  iu.investor_id,
  COUNT(DISTINCT iu.project_id)                                               AS project_count,
  SUM(iu.issued_units)                                                        AS total_units,
  COALESCE(SUM(iu.capital_invested), 0)                                       AS total_invested,
  COALESCE(SUM(iu.total_amount_received), 0)                                  AS total_capital_received,
  COALESCE(SUM(iu.capital_outstanding), 0)                                    AS total_capital_outstanding,
  COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'processed'), 0)            AS total_payouts_received,
  CASE
    WHEN COALESCE(SUM(iu.capital_invested), 0) > 0
    THEN ROUND(
      COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'processed'), 0)
      / SUM(iu.capital_invested) * 100, 2
    )
    ELSE 0
  END                                                                         AS roi_pct,
  MIN(p.payout_date) FILTER (WHERE p.status = 'pending')                     AS next_payout_date,
  (
    SELECT amount FROM public.payouts
    WHERE investor_id = iu.investor_id
      AND status = 'pending'
    ORDER BY payout_date ASC NULLS LAST
    LIMIT 1
  )                                                                           AS next_payout_amount
FROM public.investor_units iu
LEFT JOIN public.payouts p ON p.investor_id = iu.investor_id
GROUP BY iu.investor_id;

COMMENT ON VIEW public.portfolio_summary IS
  'Pre-computed portfolio aggregates per investor. SECURITY INVOKER — '
  'runs as querying user so RLS on investor_units and payouts is enforced.';

-- Fix 3: set_updated_at — lock search_path to prevent search_path injection
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = ''
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;
