-- Force the portfolio_summary view to honour the caller's RLS, not the
-- view owner's. Owner is `postgres` which has BYPASSRLS, so the default
-- SECURITY DEFINER behaviour was returning every investor's row to every
-- authenticated caller. With security_invoker=on, the view executes with
-- the caller's privileges and RLS on `investor_units` and `payouts`
-- correctly filters to the caller's own rows.
--
-- Reversible: ALTER VIEW public.portfolio_summary SET (security_invoker = off);

ALTER VIEW public.portfolio_summary SET (security_invoker = on);

COMMENT ON VIEW public.portfolio_summary IS
  'Per-investor aggregated portfolio. SECURITY INVOKER — relies on RLS '
  'on the underlying `investor_units` and `payouts` tables to scope rows '
  'to the calling user. DO NOT change to security_invoker=off without '
  'auditing the leak vector first.';
