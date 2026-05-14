// bank-change-request — P1
//
// Investor requests a change to their payout bank account. We never
// update `investors` directly here — staff verify and update Zoho CRM,
// which propagates to Supabase via the zoho-crm-webhook. This function
// just records the pending request and emails ops.
//
// 7-day cooldown: an investor with one already-pending request is
// throttled. Cooldown is enforced server-side (was previously also
// guarded by an INSERT policy that we now drop in
// migration 017_drop_edge_only_insert_policies — this function is the
// only path investors have to bank_change_requests).
//
// Auth: standard Supabase JWT (verify_jwt: true).

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

// Last-4-digits guard. The Flutter form is supposed to mask the input
// before sending, but we double-check here so we never accept a raw
// account number even if the client misbehaves.
function isAlreadyMasked(s: string): boolean {
  return /^X+(-X+)*-\d{4}$/.test(s.trim());
}

interface ChangeBody {
  bank_name: string;
  account_masked: string;
  ifsc: string;
  holder_name: string;
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
    let body: ChangeBody;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(req, { error: "invalid json" }, { status: 400 });
    }
    const { bank_name, account_masked, ifsc, holder_name } = body;
    if (!bank_name || !account_masked || !ifsc || !holder_name) {
      return jsonResponse(
        req,
        { error: "bank_name, account_masked, ifsc, holder_name are required" },
        { status: 400 },
      );
    }
    if (!isAlreadyMasked(account_masked)) {
      return jsonResponse(
        req,
        {
          error: "account_masked must already be masked (e.g. XXXX-XXXX-1234)",
          message:
            "The Flutter form should mask the account number before submitting; we never accept raw account numbers here.",
        },
        { status: 400 },
      );
    }

    // ── 7-day cooldown ─────────────────────────────────────────────
    const cooldownSince = new Date(
      Date.now() - 7 * 24 * 60 * 60 * 1000,
    ).toISOString();
    const { data: recent } = await supabase
      .from("bank_change_requests")
      .select("id, status, requested_at")
      .eq("investor_id", investorId)
      .eq("status", "pending")
      .gte("requested_at", cooldownSince)
      .limit(1)
      .maybeSingle();

    if (recent) {
      return jsonResponse(
        req,
        {
          error: "rate_limited",
          message: "A pending bank-change request already exists",
          existing_request_id: recent.id,
        },
        { status: 429 },
      );
    }

    // ── Insert (service-role — bypasses RLS) ───────────────────────
    const { data: changeRequest, error: insertErr } = await supabase
      .from("bank_change_requests")
      .insert({
        investor_id: investorId,
        new_bank_name: bank_name,
        new_account_masked: account_masked,
        new_ifsc: ifsc,
        new_holder_name: holder_name,
        status: "pending",
        requested_at: new Date().toISOString(),
      })
      .select("id")
      .single();

    if (insertErr || !changeRequest) {
      return jsonResponse(
        req,
        { error: "insert failed", detail: insertErr?.message },
        { status: 500 },
      );
    }

    // ── Notify ops ─────────────────────────────────────────────────
    const { data: investor } = await supabase
      .from("investors")
      .select("name, arl_id")
      .eq("id", investorId)
      .maybeSingle();

    await sendEmail(
      ARL_OPS_EMAIL,
      `[ARL] Bank Change Request — ${investor?.name ?? "Investor"} (${investor?.arl_id ?? ""})`,
      `<h3>Bank change request</h3>
       <p><b>Investor:</b> ${escapeHtml(investor?.name ?? "(unknown)")} (${escapeHtml(investor?.arl_id ?? "")})</p>
       <p><b>New Bank:</b> ${escapeHtml(bank_name)}</p>
       <p><b>Account (masked):</b> ${escapeHtml(account_masked)}</p>
       <p><b>IFSC:</b> ${escapeHtml(ifsc)}</p>
       <p><b>Account Holder:</b> ${escapeHtml(holder_name)}</p>
       <p><b>Request ID:</b> ${changeRequest.id}</p>
       <p>Verify with the investor and update Zoho CRM. The Supabase row will sync via webhook.</p>`,
    );

    return jsonResponse(req, { request_id: changeRequest.id });
  } catch (err: unknown) {
    // E.T2: Capture exception in Sentry if configured.
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    return jsonResponse(req, { error: errMsg }, { status: 500 });
  }
});
