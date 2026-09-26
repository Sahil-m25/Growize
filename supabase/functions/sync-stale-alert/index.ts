// sync-stale-alert — sync health monitor (v9, 2026-09-26).
//
// Runs hourly via pg_cron. Checks whether each Zoho-backed sync JOB is
// healthy, and emails ops ONCE per incident when one is not.
//
// Why v9: v8 alerted on the age of max(last_synced_at). On a small, quiet
// dataset (4 investors) nothing changes for days, so it fired every hour
// forever (~8,000 rows) and nobody read them. Meanwhile the real failure —
// the Zoho refresh token dying on 2026-08-13 — went unnoticed for 45 days,
// because the daily health-check it relied on was never deployed (404).
//
// v9 signal: the latest webhook_log row for each sync job.
//   * unhealthy if the latest run FAILED, or
//   * unhealthy if there has been no successful run for > MAX_SILENCE.
// De-dupe: a sync_alerts row is written (and an email sent) only when a
// job has no alert in the last REALERT window, so an outage produces one
// email a day, not 24.
//
// Auth: shared-secret header `x-arl-cron-secret` = CRON_SECRET env var.
// Email: Resend, to ARL_OPS_EMAIL (same channel as create-ticket).
// Deploy: supabase functions deploy sync-stale-alert --no-verify-jwt

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET");
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const ARL_OPS_EMAIL = Deno.env.get("ARL_OPS_EMAIL") ?? "ops@agresearchlabs.com";

// All three run once a day (01:00, 00:30, 00:45 UTC). 26h = one missed run + slack.
const MAX_SILENCE_SECS = 26 * 3600;
const REALERT_SECS = 24 * 3600;

const JOBS: Array<{ key: string; source: string; event: string; label: string }> = [
  { key: "zoho_reconcile", source: "zoho_crm", event: "reconcile_daily", label: "Zoho → app nightly sync (investors, projects, units)" },
  { key: "gallery_sync", source: "gallery_sync", event: "daily_sync", label: "Farm photo sync" },
  { key: "documents_sync", source: "documents_sync", event: "daily_sync", label: "Document sync" },
];

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

function escapeHtml(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

async function sendEmail(subject: string, html: string): Promise<boolean> {
  if (!RESEND_API_KEY) {
    console.warn("RESEND_API_KEY not set — skipping email send");
    return false;
  }
  try {
    const res = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ from: "ARL <noreply@agresearchlabs.com>", to: [ARL_OPS_EMAIL], subject, html }),
    });
    if (!res.ok) console.error(`email send failed: ${res.status} ${await res.text()}`);
    return res.ok;
  } catch (e) {
    console.error("email send failed:", e);
    return false;
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return jsonResponse({ error: "method not allowed" }, { status: 405 });
  const got = req.headers.get("x-arl-cron-secret") ?? "";
  if (!CRON_SECRET || !timingSafeEqual(got, CRON_SECRET)) {
    return jsonResponse({ error: "unauthorized" }, { status: 401 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const now = Date.now();
  const summary: Record<string, unknown>[] = [];
  const newAlerts: Array<{ job: typeof JOBS[number]; detail: string; lastOk: string | null; age: number }> = [];

  for (const job of JOBS) {
    const [{ data: latest, error: e1 }, { data: lastOk, error: e2 }] = await Promise.all([
      supabase.from("webhook_log").select("status, received_at, error_message")
        .eq("source", job.source).eq("event_type", job.event)
        .order("received_at", { ascending: false }).limit(1).maybeSingle(),
      supabase.from("webhook_log").select("received_at")
        .eq("source", job.source).eq("event_type", job.event).eq("status", "processed")
        .order("received_at", { ascending: false }).limit(1).maybeSingle(),
    ]);
    if (e1 || e2) {
      summary.push({ job: job.key, error: (e1 ?? e2)!.message });
      continue;
    }
    const lastOkAt = lastOk?.received_at ? new Date(lastOk.received_at as string).getTime() : null;
    const age = lastOkAt ? Math.floor((now - lastOkAt) / 1000) : MAX_SILENCE_SECS + 1;
    const latestFailed = latest?.status === "failed";
    const silent = age > MAX_SILENCE_SECS;
    const unhealthy = latestFailed || silent;

    let detail = "";
    if (latestFailed) detail = `Latest run failed: ${String(latest?.error_message ?? "no error message").slice(0, 400)}`;
    else if (silent) detail = lastOkAt ? `No successful run for ${Math.round(age / 3600)}h` : "No successful run on record";

    summary.push({ job: job.key, healthy: !unhealthy, last_ok: lastOk?.received_at ?? null, latest_status: latest?.status ?? null });
    if (!unhealthy) continue;

    // De-dupe: one alert per job per REALERT window.
    const since = new Date(now - REALERT_SECS * 1000).toISOString();
    const { count } = await supabase.from("sync_alerts").select("id", { count: "exact", head: true })
      .eq("table_name", job.key).gte("created_at", since);
    if ((count ?? 0) > 0) continue;
    newAlerts.push({ job, detail, lastOk: (lastOk?.received_at as string) ?? null, age });
  }

  if (newAlerts.length > 0) {
    const { error: insErr } = await supabase.from("sync_alerts").insert(newAlerts.map((a) => ({
      table_name: a.job.key,
      max_synced_at: a.lastOk,
      age_seconds: a.age,
      threshold_secs: MAX_SILENCE_SECS,
      detail: a.detail,
    })));
    if (insErr) console.error(`sync_alerts insert failed: ${insErr.message}`);

    const rows = newAlerts.map((a) =>
      `<li><b>${escapeHtml(a.job.label)}</b><br>${escapeHtml(a.detail)}<br>` +
      `Last successful run: ${a.lastOk ? escapeHtml(new Date(a.lastOk).toUTCString()) : "never"}</li>`).join("");
    await sendEmail(
      `[Growize] Sync problem: ${newAlerts.map((a) => a.job.key).join(", ")}`,
      `<p>One or more Growize data syncs from Zoho are not healthy. Investor-facing data may be out of date.</p>` +
      `<ul>${rows}</ul>` +
      `<p>Check Supabase &rarr; Table editor &rarr; <code>webhook_log</code> for the full error. ` +
      `A common cause is the Zoho user behind <code>ZOHO_REFRESH_TOKEN</code> being deactivated.</p>` +
      `<p>You will get at most one email per job per day while the problem lasts.</p>`,
    );
  }

  return jsonResponse({ status: "ok", new_alerts: newAlerts.length, summary });
});
