// health-check — E.T3
//
// Daily cron-triggered health check. Queries webhook_log and cron.job_run_details
// for failed rows in the last 24 hours. If found, sends an ops email summary and
// returns JSON status. Returns green if all checks pass.
//
// Auth: shared-secret header x-arl-cron-secret matched against CRON_SECRET env var.
//
// Deploy: supabase functions deploy health-check --no-verify-jwt
// Cron: scheduled via migration 022_health_check_cron.sql

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET");
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const ARL_OPS_EMAIL = Deno.env.get("ARL_OPS_EMAIL") ?? "ops@agresearchlabs.com";

// E.T2: Initialize Sentry if DSN is configured.
const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({
    dsn: SENTRY_EDGE_DSN,
    tracesSampleRate: 0.1,
  });
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) {
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

async function sendEmail(to: string, subject: string, html: string): Promise<void> {
  if (!RESEND_API_KEY) {
    console.warn("RESEND_API_KEY not set — skipping email send");
    return;
  }
  try {
    await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "content-type": "application/json",
      },
      body: JSON.stringify({
        from: "ARL <noreply@agresearchlabs.com>",
        to: [to],
        subject,
        html,
      }),
    });
  } catch (e) {
    console.error("email send failed:", e);
  }
}

Deno.serve(async (req: Request) => {
  // Shared-secret gate — constant-time compare.
  const expected = CRON_SECRET;
  const got = req.headers.get("x-arl-cron-secret") ?? "";
  if (!expected || !timingSafeEqual(got, expected)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  // Accept GET (for cron) or POST (for manual trigger)
  if (req.method !== "GET" && req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const now = new Date();
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000).toISOString();

    // 1. Check webhook_log for failed rows in last 24h
    const { data: failedWebhooks, error: webhookErr } = await supabase
      .from("webhook_log")
      .select("id, source, event_type, error_message, received_at", { count: "exact" })
      .eq("status", "failed")
      .gte("received_at", oneDayAgo);

    if (webhookErr) {
      throw new Error(`webhook_log query failed: ${webhookErr.message}`);
    }

    // 2. Check cron.job_run_details for failed rows in last 24h
    // Using cast as any since this is an info_schema table not in the regular schema
    const { data: failedCrons, error: cronErr } = await supabase
      .from("cron.job_run_details" as any)
      .select("job_id, status, return_message, start_time")
      .eq("status", "failed")
      .gte("start_time", oneDayAgo);

    if (cronErr) {
      throw new Error(`cron query failed: ${cronErr.message}`);
    }

    const failedWebhookCount = failedWebhooks?.length ?? 0;
    const failedCronCount = failedCrons?.length ?? 0;
    const overallStatus = failedWebhookCount + failedCronCount > 0 ? "red" : "green";

    // 3. If there are failures, send an email summary
    if (failedWebhookCount + failedCronCount > 0) {
      let emailHtml = `<h2>Health Check Alert</h2>
        <p>The following issues were detected in the last 24 hours:</p>`;

      if (failedWebhookCount > 0) {
        emailHtml += `<h3>Failed Webhooks (${failedWebhookCount})</h3><ul>`;
        for (const webhook of failedWebhooks ?? []) {
          emailHtml += `<li><b>${escapeHtml(webhook.source)}/${escapeHtml(webhook.event_type)}</b>
            — ${escapeHtml(webhook.error_message ?? "unknown error")}
            (${webhook.received_at})</li>`;
        }
        emailHtml += "</ul>";
      }

      if (failedCronCount > 0) {
        emailHtml += `<h3>Failed Cron Jobs (${failedCronCount})</h3><ul>`;
        for (const cron of failedCrons ?? []) {
          emailHtml += `<li><b>Job ${cron.job_id}</b> — ${escapeHtml(cron.return_message ?? "unknown error")}
            (${cron.start_time})</li>`;
        }
        emailHtml += "</ul>";
      }

      emailHtml += `<p>Review the logs and take corrective action as needed.</p>`;

      await sendEmail(
        ARL_OPS_EMAIL,
        `[ARL Health Check] ${overallStatus.toUpperCase()} — ${failedWebhookCount + failedCronCount} issues`,
        emailHtml,
      );
    }

    return new Response(
      JSON.stringify({
        status: overallStatus,
        failed_webhooks: failedWebhookCount,
        failed_crons: failedCronCount,
        checked_at: now.toISOString(),
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    // E.T2: Capture exception in Sentry if configured.
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    return new Response(JSON.stringify({ error: errMsg, status: "red" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
