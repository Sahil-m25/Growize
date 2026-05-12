// sync-stale-alert — stale-data observability cron.
//
// Runs hourly via pg_cron. Reads the sync_status view (introduced in
// migration 023) and inserts a sync_alerts row for every monitored
// table whose max(last_synced_at) is older than the per-table threshold.
// health-check picks up the rows and surfaces them in its daily ops
// summary.
//
// Threshold rationale:
//   * llps / projects: 24h (slow-changing reference data).
//   * investors:       6h  (KYC/bank field flips faster).
//   * investor_units:  2h  (payouts + status changes are time-sensitive).
//
// Auth: shared-secret header `x-arl-cron-secret` = CRON_SECRET env var.
// Deploy: supabase functions deploy sync-stale-alert --no-verify-jwt
// Cron: scheduled in migration 024_sync_alerts_and_reconcile_cron.sql.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET");

const THRESHOLDS_SECONDS: Record<string, number> = {
  llps: 24 * 3600,
  projects: 24 * 3600,
  investors: 6 * 3600,
  investor_units: 2 * 3600,
};

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: { "content-type": "application/json", ...(init.headers ?? {}) },
  });
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, { status: 405 });
  }
  const got = req.headers.get("x-arl-cron-secret") ?? "";
  if (!CRON_SECRET || !timingSafeEqual(got, CRON_SECRET)) {
    return jsonResponse({ error: "unauthorized" }, { status: 401 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: rows, error } = await supabase
    .from("sync_status")
    .select("table_name, rows, max_synced_at");
  if (error) return jsonResponse({ error: error.message }, { status: 500 });

  const now = Date.now();
  const alerts: Record<string, unknown>[] = [];
  const summary: Array<{ table: string; rows: number; age_seconds: number | null; threshold: number; alert: boolean }> = [];

  for (const r of rows ?? []) {
    const t = r.table_name as string;
    const max = r.max_synced_at ? new Date(r.max_synced_at as string).getTime() : null;
    const ageSeconds = max ? Math.floor((now - max) / 1000) : null;
    const threshold = THRESHOLDS_SECONDS[t] ?? 24 * 3600;
    const stale = ageSeconds === null || ageSeconds > threshold;

    summary.push({
      table: t,
      rows: (r.rows as number) ?? 0,
      age_seconds: ageSeconds,
      threshold,
      alert: stale,
    });

    if (stale) {
      alerts.push({
        table_name: t,
        max_synced_at: r.max_synced_at,
        age_seconds: ageSeconds ?? threshold + 1,
        threshold_secs: threshold,
        detail: ageSeconds === null
          ? "no rows have last_synced_at set"
          : `max(last_synced_at) is ${ageSeconds}s old, threshold ${threshold}s`,
      });
    }
  }

  if (alerts.length > 0) {
    const { error: alertErr } = await supabase.from("sync_alerts").insert(alerts);
    if (alertErr) console.error(`sync_alerts insert failed: ${alertErr.message}`);
  }

  return jsonResponse({ status: "ok", alerts: alerts.length, summary });
});
