
-- ============================================================
-- MIGRATION 008 — PORTFOLIO SUMMARY VIEW
-- Read-only computed view. Flutter reads this instead of
-- doing math in the app. Aggregates across all of an
-- investor's units and payouts in one query.
-- ============================================================

CREATE VIEW public.portfolio_summary AS
SELECT
  iu.investor_id,

  -- Project count
  COUNT(DISTINCT iu.project_id)                                               AS project_count,

  -- Unit totals
  SUM(iu.issued_units)                                                        AS total_units,

  -- Capital
  COALESCE(SUM(iu.capital_invested), 0)                                       AS total_invested,
  COALESCE(SUM(iu.total_amount_received), 0)                                  AS total_capital_received,
  COALESCE(SUM(iu.capital_outstanding), 0)                                    AS total_capital_outstanding,

  -- Payouts received (from payouts table, status=processed)
  COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'processed'), 0)            AS total_payouts_received,

  -- Simple ROI %: total payouts received / total invested * 100
  CASE
    WHEN COALESCE(SUM(iu.capital_invested), 0) > 0
    THEN ROUND(
      COALESCE(SUM(p.amount) FILTER (WHERE p.status = 'processed'), 0)
      / SUM(iu.capital_invested) * 100,
      2
    )
    ELSE 0
  END                                                                         AS roi_pct,

  -- Next payout: nearest future pending payout date across all projects
  MIN(p.payout_date) FILTER (WHERE p.status = 'pending')                     AS next_payout_date,

  -- Amount of that next payout
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
  'Pre-computed portfolio aggregates per investor. '
  'Flutter reads this directly — no in-app arithmetic needed.';
