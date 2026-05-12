// create-ticket — P1
//
// Investor (Flutter app) creates a support ticket. We rate-limit to 5
// tickets per 24h, validate the category against the DB CHECK enum,
// insert the ticket + first message via the SERVICE-ROLE client (so
// PostgreSQL RLS does NOT have to be relaxed to allow direct INSERTs
// from authenticated users — see migration 017_drop_edge_only_insert_policies),
// then email ARL ops.
//
// Auth: standard Supabase JWT (verify_jwt: true). The function pulls
//       the caller's user-id from the JWT, then performs ALL DB writes
//       via the service-role client with investor_id set explicitly to
//       that user-id. There is no path by which a caller can write a
//       row attributed to another investor.
//
// Self-contained on purpose. Helpers (CORS, escapeHtml, sendEmail) are
// duplicated across functions; consolidate into _shared/ post-launch.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ARL_OPS_EMAIL = Deno.env.get("ARL_OPS_EMAIL") ?? "ops@agresearchlabs.com";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");

// E.T2: Initialize Sentry if DSN is configured.
const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({
    dsn: SENTRY_EDGE_DSN,
    tracesSampleRate: 0.1,
  });
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function jsonResponse(body: unknown, init: ResponseInit = {}): Response {
  return new Response(JSON.stringify(body), {
    ...init,
    headers: {
      ...corsHeaders,
      "content-type": "application/json",
      ...(init.headers ?? {}),
    },
  });
}

/// Escape HTML so user-supplied text in the ops email can't inject markup.
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

const VALID_CATEGORIES = new Set([
  "payout",
  "documents",
  "general",
  "bank_change",
  "exit_request",
]);

interface CreateBody {
  category: string;
  subject: string;
  body: string;
  project_id?: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (req.method !== "POST") {
    return jsonResponse({ error: "method not allowed" }, { status: 405 });
  }

  try {
    // ── Resolve caller from JWT ─────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse({ error: "unauthorized" }, { status: 401 });
    }
    const token = authHeader.slice("Bearer ".length);

    // Service-role client. Used for ALL reads and writes — including the
    // identity check via auth.getUser(token), which talks to the auth
    // server with the supplied user JWT. Because we never override
    // Authorization on this client, all PostgREST calls run as
    // service_role and bypass RLS. That's what lets us drop the direct
    // INSERT policies on support_tickets / ticket_messages — investors
    // can no longer write to those tables except through this function.
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser(token);
    if (userErr || !userData?.user) {
      return jsonResponse({ error: "invalid token" }, { status: 401 });
    }
    const investorId = userData.user.id;

    // ── Parse + validate body ───────────────────────────────────────
    let body: CreateBody;
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "invalid json" }, { status: 400 });
    }
    const { category, subject, body: messageBody, project_id } = body;

    if (!category || !VALID_CATEGORIES.has(category)) {
      return jsonResponse(
        { error: `category must be one of: ${[...VALID_CATEGORIES].join(", ")}` },
        { status: 400 },
      );
    }
    if (!subject || typeof subject !== "string" || !subject.trim()) {
      return jsonResponse({ error: "subject is required" }, { status: 400 });
    }
    if (!messageBody || typeof messageBody !== "string" || !messageBody.trim()) {
      return jsonResponse({ error: "body is required" }, { status: 400 });
    }
    if (subject.length > 200) {
      return jsonResponse({ error: "subject too long (max 200)" }, { status: 400 });
    }
    if (messageBody.length > 5000) {
      return jsonResponse({ error: "body too long (max 5000)" }, { status: 400 });
    }

    // ── Rate limit: 5 tickets per 24 h per investor ─────────────────
    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();
    const { count, error: countErr } = await supabase
      .from("support_tickets")
      .select("id", { count: "exact", head: true })
      .eq("investor_id", investorId)
      .gte("created_at", since);
    if (countErr) {
      return jsonResponse(
        { error: "rate-limit check failed", detail: countErr.message },
        { status: 500 },
      );
    }
    if ((count ?? 0) >= 5) {
      return jsonResponse(
        { error: "rate_limited", message: "Max 5 tickets in 24 hours" },
        { status: 429 },
      );
    }

    // ── Insert ticket (service-role — bypasses RLS) ────────────────
    // investor_id is set explicitly from the verified JWT user-id, so
    // even though we have service-role privileges here the row can
    // never be attributed to a different investor.
    const { data: ticket, error: tErr } = await supabase
      .from("support_tickets")
      .insert({
        investor_id: investorId,
        project_id: project_id ?? null,
        category,
        subject: subject.trim(),
        status: "open",
      })
      .select("id")
      .single();
    if (tErr || !ticket) {
      return jsonResponse(
        { error: "ticket insert failed", detail: tErr?.message },
        { status: 500 },
      );
    }

    // ── First message ──────────────────────────────────────────────
    const { error: msgErr } = await supabase.from("ticket_messages").insert({
      ticket_id: ticket.id,
      sender_type: "investor",
      body: messageBody,
    });
    if (msgErr) {
      // Best-effort cleanup so the dashboard doesn't show a ticket with
      // no first message.
      await supabase.from("support_tickets").delete().eq("id", ticket.id);
      return jsonResponse(
        { error: "first-message insert failed", detail: msgErr.message },
        { status: 500 },
      );
    }

    // ── Notify ops ─────────────────────────────────────────────────
    const { data: investor } = await supabase
      .from("investors")
      .select("name, arl_id")
      .eq("id", investorId)
      .maybeSingle();

    let projectName: string | null = null;
    if (project_id) {
      const { data: proj } = await supabase
        .from("projects")
        .select("name")
        .eq("id", project_id)
        .maybeSingle();
      projectName = proj?.name ?? null;
    }

    await sendEmail(
      ARL_OPS_EMAIL,
      `[ARL Ticket] ${category}: ${subject}`,
      `<h3>New support ticket</h3>
       <p><b>Investor:</b> ${escapeHtml(investor?.name ?? "(unknown)")} (${escapeHtml(investor?.arl_id ?? "")})</p>
       <p><b>Category:</b> ${escapeHtml(category)}</p>
       ${projectName ? `<p><b>Project:</b> ${escapeHtml(projectName)}</p>` : ""}
       <p><b>Subject:</b> ${escapeHtml(subject)}</p>
       <pre style="background:#f5f5f0;padding:12px;border-radius:6px;white-space:pre-wrap;font-family:inherit">${escapeHtml(messageBody)}</pre>
       <p><b>Ticket ID:</b> ${ticket.id}</p>`,
    );

    return jsonResponse({ ticket_id: ticket.id });
  } catch (err: unknown) {
    // E.T2: Capture exception in Sentry if configured.
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    return jsonResponse({ error: errMsg }, { status: 500 });
  }
});
