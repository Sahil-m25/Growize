// reply-ticket — P1
//
// Investor adds a reply message to one of their own tickets. The
// function refuses to reply to a resolved ticket. All DB writes go
// via the service-role client; the direct INSERT policy on
// ticket_messages is dropped (see migration 017_drop_edge_only_insert_policies),
// so this function is the only path investors have to add messages.
//
// Auth: standard Supabase JWT (verify_jwt: true). The function pulls
//       the caller's user-id from the JWT, verifies ownership of the
//       target ticket, then inserts via service-role with
//       sender_type='investor'.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";
import { jsonResponse, preflight } from "../_shared/cors.ts";

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

interface ReplyBody {
  ticket_id: string;
  body: string;
}

Deno.serve(async (req: Request) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "method not allowed" }, { status: 405 });
  }

  try {
    // ── Resolve caller from JWT ─────────────────────────────────────
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return jsonResponse(req, { error: "unauthorized" }, { status: 401 });
    }
    const token = authHeader.slice("Bearer ".length);

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: userData, error: userErr } = await supabase.auth.getUser(token);
    if (userErr || !userData?.user) {
      return jsonResponse(req, { error: "invalid token" }, { status: 401 });
    }
    const investorId = userData.user.id;

    // ── Parse + validate body ───────────────────────────────────────
    let body: ReplyBody;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(req, { error: "invalid json" }, { status: 400 });
    }
    const { ticket_id, body: messageBody } = body;
    if (!ticket_id || typeof ticket_id !== "string") {
      return jsonResponse(req, { error: "ticket_id is required" }, { status: 400 });
    }
    if (!messageBody || typeof messageBody !== "string" || !messageBody.trim()) {
      return jsonResponse(req, { error: "body is required" }, { status: 400 });
    }
    if (messageBody.length > 5000) {
      return jsonResponse(req, { error: "body too long (max 5000)" }, { status: 400 });
    }

    // ── Verify ticket ownership and status ──────────────────────────
    const { data: ticket } = await supabase
      .from("support_tickets")
      .select("id, investor_id, status, subject, category")
      .eq("id", ticket_id)
      .maybeSingle();

    if (!ticket) {
      // Same response whether the ticket doesn't exist or belongs to
      // someone else — no info leak about which.
      return jsonResponse(req, { error: "ticket not found" }, { status: 404 });
    }
    if (ticket.investor_id !== investorId) {
      return jsonResponse(req, { error: "ticket not found" }, { status: 404 });
    }
    if (ticket.status === "resolved") {
      return jsonResponse(
        req,
        { error: "ticket_resolved", message: "Cannot reply to a resolved ticket" },
        { status: 400 },
      );
    }

    // ── Insert reply message (service-role — bypasses RLS) ──────────
    const { data: msg, error: insErr } = await supabase
      .from("ticket_messages")
      .insert({
        ticket_id,
        sender_type: "investor",
        body: messageBody,
      })
      .select("id")
      .single();
    if (insErr || !msg) {
      return jsonResponse(
        req,
        { error: "reply insert failed", detail: insErr?.message },
        { status: 500 },
      );
    }

    // Bump the parent ticket's updated_at so the staff inbox sorts correctly.
    await supabase
      .from("support_tickets")
      .update({ updated_at: new Date().toISOString() })
      .eq("id", ticket_id);

    // ── Notify ops ─────────────────────────────────────────────────
    const { data: investor } = await supabase
      .from("investors")
      .select("name, arl_id")
      .eq("id", investorId)
      .maybeSingle();

    await sendEmail(
      ARL_OPS_EMAIL,
      `[ARL Ticket Reply] ${ticket.category}: ${ticket.subject}`,
      `<p><b>Investor:</b> ${escapeHtml(investor?.name ?? "(unknown)")} (${escapeHtml(investor?.arl_id ?? "")})</p>
       <p><b>Ticket:</b> ${escapeHtml(ticket.subject)}</p>
       <p><b>Ticket ID:</b> ${ticket_id}</p>
       <pre style="background:#f5f5f0;padding:12px;border-radius:6px;white-space:pre-wrap;font-family:inherit">${escapeHtml(messageBody)}</pre>`,
    );

    return jsonResponse(req, { message_id: msg.id });
  } catch (err: unknown) {
    // E.T2: Capture exception in Sentry if configured.
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    return jsonResponse(req, { error: errMsg }, { status: 500 });
  }
});
