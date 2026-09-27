// @ts-nocheck — source recovered from the deployed v35 bundle (types were
// stripped by the bundler); behaviour-identical except handleContact (v36).
// zoho-crm-webhook — P0
//
// Receives webhook payloads from Zoho CRM workflow rules on Contacts,
// LLP_Creation_Module, and LLP_UnitAllocation_Module. Mirrors the data
// into Supabase, unpacks payouts from the 1..10 UTR/Amount/Date fields,
// and de-dupes via webhook_log.idempotency_key.
//
// Auth: X-ARL-Webhook-Secret header must equal WEBHOOK_SECRET env var,
//       compared in constant time.
//
// PII handling: the inbound body may contain raw PAN, bank account
// number, and Aadhaar number. Those are masked BEFORE the audit row is
// written to webhook_log, so the log never retains unmasked PII even
// for the 90-day retention window.
//
// Deploy: supabase functions deploy zoho-crm-webhook --no-verify-jwt
// Set secret: supabase secrets set WEBHOOK_SECRET=<long random hex>
//
// v32 (2026-05-20) — backend wiring batch:
//   * handleProject: detect transition INTO marketplace listing and
//     call public.broadcast_new_project_notification RPC so every
//     investor with an allocation gets a 'new_project' notification.
//   * handleProject: parse phase_1_status..phase_10_status and
//     phase_1_completed_at..phase_10_completed_at, upsert 10 rows into
//     public.project_phases, and on the transition INTO 'current'
//     call public.broadcast_phase_update_notification RPC.
//   * The canonical phase names come from PhaseTimeline6._fullLabels
//     in the Flutter app (stage 1: Land Closed → stage 10: Compliance
//     Closed + Go-live).
//
// v35 (2026-06-18) — Aadhaar masking fix:
//   * maskAadhaar() helper added — keeps last 4 digits, e.g.
//     123456789012 → XXXX-XXXX-9012. aadhaar_masked now stores the
//     masked value instead of the raw 12-digit number.
//
// v36 (2026-09-26) — App Access gate (hold before welcome):
//   * A NEW Zoho Contact no longer triggers Supabase's invite email.
//     The auth user is created silently and SUSPENDED (banned), so it
//     cannot sign in even via the raw auth API; the investors row, units
//     and payouts sync as normal so ops can check them first.
//   * Access is driven by Zoho `Contacts.App_Access` (Hold | Invite),
//     read from the Zoho API (ZOHO_* secrets) — the Deluge push function
//     does not need to change. Missing/unknown = Hold for new contacts,
//     "no change" for existing ones.
//   * Hold -> Invite: unsuspend, send ONE Growize welcome email (Resend),
//     set investors.app_access='invited' + invited_at, and write
//     App_Welcome_At / App_Welcome_Channel=Email back to Zoho.
//   * Invite -> Hold: suspend again (blocks new sign-ins).
//
// CORS / preflight / jsonResponse are imported from `../_shared/cors.ts`
// (audit S-005 remediation, docs/security_audit_2026-05-13.md). Zoho
// posts server-to-server so the Origin header is absent — the helper
// then omits Allow-Origin entirely, which is fine for non-browser
// callers. Browser-driven preflights only succeed for origins in the
// APP_ALLOWED_ORIGINS allow-list.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";
import { jsonResponse, preflight } from "../_shared/cors.ts";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET");
// v36: Zoho read-back of App_Access + welcome email.
const ZOHO_CLIENT_ID = Deno.env.get("ZOHO_CLIENT_ID");
const ZOHO_CLIENT_SECRET = Deno.env.get("ZOHO_CLIENT_SECRET");
const ZOHO_REFRESH_TOKEN = Deno.env.get("ZOHO_REFRESH_TOKEN");
const ZOHO_API = "https://www.zohoapis.in/crm/v3";
const ZOHO_TOKEN_URL = "https://accounts.zoho.in/oauth/v2/token";
const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY");
const RESEND_FROM_EMAIL = Deno.env.get("RESEND_FROM_EMAIL") ?? "Growize <noreply@agresearchlabs.com>";
const APP_WEB_URL = Deno.env.get("APP_WEB_URL") ?? "https://growizefarm.com";
const SUPPORT_EMAIL = Deno.env.get("SUPPORT_EMAIL") ?? "hello@agresearchlabs.com";
const SUSPENDED = "876000h"; // ~100 years; lifted on Invite
// E.T2: Initialize Sentry if DSN is configured.
const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({
    dsn: SENTRY_EDGE_DSN,
    tracesSampleRate: 0.1
  });
}
/// Constant-time string compare. Avoids leaking timing info about the secret.
function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let r = 0;
  for(let i = 0; i < a.length; i++){
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}
// ── PII masking helpers ────────────────────────────────────────────────
/// PAN: keep first 5, last 1, mask the middle.  RTYUI2468L → RTYUI****L
function maskPan(pan) {
  if (!pan) return null;
  const trimmed = String(pan).trim().toUpperCase();
  if (trimmed.length < 6) return trimmed; // too short — store as-is, still likely not real
  return `${trimmed.slice(0, 5)}****${trimmed.slice(-1)}`;
}
/// Bank account: keep last 4 digits.  123456789012 → XXXX-XXXX-9012
function maskBankAccount(acc) {
  if (!acc) return null;
  const digits = String(acc).replace(/\D/g, "");
  if (digits.length < 4) return null;
  const last4 = digits.slice(-4);
  return digits.length >= 12 ? `XXXX-XXXX-${last4}` : `XXXX-${last4}`;
}
/// Aadhaar: keep last 4 digits.  123456789012 → XXXX-XXXX-9012
function maskAadhaar(aadh) {
  if (!aadh) return null;
  const digits = String(aadh).replace(/\D/g, "");
  if (digits.length < 4) return null;
  return `XXXX-XXXX-${digits.slice(-4)}`;
}
/// Strip "%" and parse as number, returning null on failure.
function parsePercent(v) {
  if (v === null || v === undefined) return null;
  const s = String(v).replace(/%/g, "").trim();
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}
/// Coerce a Zoho field value to a number for Postgres numeric columns.
/// Empty strings, null, and undefined all become undefined (so the
/// upsert omits the field, letting Postgres apply NULL or default).
/// Deluge sends `""` for unset numeric fields which Postgres rejects
/// with `invalid input syntax for type numeric: ""` — this guard
/// converts those into omissions before the upsert.
function asNumber(v) {
  if (v === null || v === undefined || v === "") return undefined;
  if (typeof v === "number") return Number.isFinite(v) ? v : undefined;
  if (typeof v === "string") {
    const n = Number(v);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}
/// Coerce a Zoho field value to a date string for Postgres date /
/// timestamp columns. Empty strings, null, and undefined all become
/// undefined (so the upsert omits the field, letting Postgres apply
/// NULL or default). Same failure mode as asNumber: Deluge sends `""`
/// for unset date fields which Postgres rejects with
/// `invalid input syntax for type date: ""`.
function asDate(v) {
  if (v === null || v === undefined) return undefined;
  if (typeof v !== "string") return String(v);
  const trimmed = v.trim();
  return trimmed === "" ? undefined : trimmed;
}
/// Zoho's `Launch_Year` is a year-only picklist (e.g. "2026"). The
/// Supabase `projects.launch_year` column is a DATE — passing just
/// "2026" raises `invalid input syntax for type date`. Coerce a bare
/// 4-digit year to Jan 1 of that year; passthrough full ISO dates.
function asLaunchYearDate(v) {
  if (v === null || v === undefined) return undefined;
  const s = (typeof v === "string" ? v : String(v)).trim();
  if (s === "") return undefined;
  if (/^\d{4}$/.test(s)) return `${s}-01-01`;
  return s;
}
/// Closes DEF-2026-05-11-01. New LLPs synced via webhook had
/// `is_listed_in_marketplace` defaulting to false → never reached the
/// Explore tab. Derive from LLP_Status: true when the project is
/// actively soliciting new investors. Existing investors-only states
/// (Active = post-allocation operational, Fully Subscribed / Closed,
/// Darft [sic — typo in Zoho picklist]) stay off the marketplace.
/// Keep in sync with isListedInMarketplace() in zoho-reconcile-daily.
function isListedInMarketplace(status) {
  if (typeof status !== "string") return false;
  const s = status.trim();
  return s === "Open for Reservation" || s === "Open for Issuance";
}
function mapKycStatus(v) {
  const raw = (typeof v === "string" ? v : "").trim().toLowerCase();
  if (!raw) return "pending";
  // Canonical (already lowercase enum value) — pass through.
  if (raw === "pending" || raw === "in_progress" || raw === "verified" || raw === "rejected") {
    return raw;
  }
  // Zoho-specific surface forms.
  if (raw === "in progress") return "in_progress";
  if (raw === "completed") return "verified";
  if (raw === "not started") return "pending";
  return "pending";
}
// ── Phase mapping (v32, Phase 3 wiring) ────────────────────────────────
//
// PHASE_NAMES is the canonical 10-stage timeline from the Flutter
// app's PhaseTimeline6._fullLabels — keep ordering in lockstep.
// Stage 1: Land Closed
// Stage 2: Design & Plan Locked
// Stage 3: Site Prep
// Stage 4: Core Civil
// Stage 5: Procurement Locked
// Stage 6: Water Source & Storage Ready
// Stage 7: Power Ready
// Stage 8: Greenhouse
// Stage 9: Production Systems Installed
// Stage 10: Compliance Closed + Go-live
const PHASE_NAMES = [
  "Land Closed",
  "Design & Plan Locked",
  "Site Prep",
  "Core Civil",
  "Procurement Locked",
  "Water Source & Storage Ready",
  "Power Ready",
  "Greenhouse",
  "Production Systems Installed",
  "Compliance Closed + Go-live"
];
/// Map Zoho Phase_X_Status picklist values to the project_phases.status
/// CHECK enum (`done | current | pending`). The Zoho picklist options
/// are "Not Started", "In Progress", "Done"; anything we don't recognise
/// falls back to 'pending' so the upsert never violates the CHECK.
function mapPhaseStatus(v) {
  const s = (typeof v === "string" ? v : "").trim().toLowerCase();
  if (s === "done" || s === "completed") return "done";
  if (s === "in progress" || s === "in_progress" || s === "current") return "current";
  return "pending"; // covers "not started", "", null, unknown
}
/// Returns a deep-cloned copy of the webhook body with sensitive PII
/// fields inside `data` masked. Used for `webhook_log.payload` so the
/// audit log never retains raw PAN, bank account, or Aadhaar numbers.
function sanitizeForLogging(body) {
  try {
    const clone = JSON.parse(JSON.stringify(body));
    if (clone && clone.data && typeof clone.data === "object") {
      const d = clone.data;
      if (d.PAN_Number) d.PAN_Number = maskPan(d.PAN_Number) ?? "[REDACTED]";
      if (d.Bank_Account_Number) d.Bank_Account_Number = maskBankAccount(d.Bank_Account_Number) ?? "[REDACTED]";
      if (d.Aadhaar_Number) d.Aadhaar_Number = "[REDACTED]";
      // Defence in depth — any future field whose name suggests it carries
      // raw account/identity numbers is automatically blanked. Better a
      // false positive in the audit log than a leak.
      for (const key of Object.keys(d)){
        const k = key.toLowerCase();
        if (k.includes("aadhaar") || k.includes("aadhar")) {
          d[key] = "[REDACTED]";
        }
      }
    }
    return clone;
  } catch  {
    // If something is non-serialisable, fall back to a minimal record
    // rather than leaking the original.
    return {
      _redacted: true,
      reason: "sanitize_failed"
    };
  }
}
/// Normalises the four accepted request shapes into one envelope:
///
///   1. **Envelope** — `body = { module, operation, data: {...} }`. The
///      shape Zoho Flow / our reconcile job already use. Source label:
///      `envelope`.
///   2. **Flat** — module + operation arrive on the URL as query params
///      (`?module=Contacts&operation=update`); the request body is the
///      record itself with fields at the top level. Source label:
///      `flat`.
///   3. **Mixed** — module/operation present in BOTH query params AND
///      body; data still under `body.data`. We accept it for resilience
///      but query params win. Source label: `mixed`.
///   4. **Query-only** — request body is empty/null and ALL record
///      fields ride on the URL query string. Source label: `query`.
function normaliseRequest(url, body) {
  const queryModule = url.searchParams.get("module") ?? undefined;
  const queryOp = url.searchParams.get("operation") ?? undefined;
  const bodyModule = typeof body.module === "string" ? body.module : undefined;
  const bodyOp = typeof body.operation === "string" ? body.operation : undefined;
  const hasEnvelopeData = body.data !== undefined && body.data !== null && typeof body.data === "object";
  const bodyKeys = Object.keys(body).filter((k)=>k !== "module" && k !== "operation" && k !== "data");
  const bodyHasFlatFields = bodyKeys.length > 0;
  let data;
  let source;
  if (hasEnvelopeData) {
    const envelopeData = body.data;
    data = Array.isArray(envelopeData) ? envelopeData[0] ?? {} : envelopeData;
    source = queryModule || queryOp ? "mixed" : "envelope";
  } else if (bodyHasFlatFields) {
    data = {};
    for (const k of bodyKeys)data[k] = body[k];
    source = "flat";
  } else {
    data = {};
    for (const [k, v] of url.searchParams.entries()){
      if (k === "module" || k === "operation") continue;
      data[k] = v;
    }
    source = "query";
  }
  return {
    module: (queryModule ?? bodyModule ?? "").trim(),
    operation: (queryOp ?? bodyOp ?? "").trim(),
    data,
    source
  };
}
// ── Handler ────────────────────────────────────────────────────────────
Deno.serve(async (req)=>{
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return jsonResponse(req, {
      error: "method not allowed"
    }, {
      status: 405
    });
  }
  // Shared-secret gate — constant-time compare.
  const got = req.headers.get("x-arl-webhook-secret") ?? "";
  if (!WEBHOOK_SECRET || !timingSafeEqual(got, WEBHOOK_SECRET)) {
    return jsonResponse(req, {
      error: "unauthorized"
    }, {
      status: 401
    });
  }
  // Body parsing is permissive because the query-only path (Zoho
  // Webhook with Body Type=None) sends no body at all.
  let rawBody;
  try {
    const text = await req.text();
    if (text.trim() === "") {
      rawBody = {};
    } else {
      const parsed = JSON.parse(text);
      rawBody = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
    }
  } catch  {
    rawBody = {};
  }
  const url = new URL(req.url);
  const { module: zohoModule, operation, data, source: shapeSource } = normaliseRequest(url, rawBody);
  if (!zohoModule || typeof data !== "object") {
    return jsonResponse(req, {
      error: "missing module or data"
    }, {
      status: 400
    });
  }
  const recordId = data["id"] ?? "";
  const modifiedTime = data["Modified_Time"] ?? "";
  if (!recordId) {
    return jsonResponse(req, {
      error: "missing record id"
    }, {
      status: 400
    });
  }
  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: {
      autoRefreshToken: false,
      persistSession: false
    }
  });
  const idempotencyKey = `${zohoModule}_${recordId}_${modifiedTime}`;
  // De-dupe — if we've already processed this exact (module, recordId,
  // modifiedTime) tuple, return early.
  const { data: existing } = await supabase.from("webhook_log").select("id, status").eq("idempotency_key", idempotencyKey).maybeSingle();
  if (existing && existing.status === "processed") {
    return jsonResponse(req, {
      status: "duplicate"
    });
  }
  // ── Log received (with masked payload) ───────────────────────────────
  const sanitized = sanitizeForLogging({
    module: zohoModule,
    operation,
    data,
    _shape: shapeSource
  });
  const { data: logRow, error: logErr } = await supabase.from("webhook_log").upsert({
    source: "zoho_crm",
    event_type: operation ? `${zohoModule}.${operation}` : zohoModule,
    zoho_record_id: recordId,
    idempotency_key: idempotencyKey,
    payload: sanitized,
    status: "received",
    received_at: new Date().toISOString()
  }, {
    onConflict: "idempotency_key"
  }).select("id").single();
  if (logErr || !logRow) {
    return jsonResponse(req, {
      error: "log insert failed",
      detail: logErr?.message
    }, {
      status: 500
    });
  }
  const logId = logRow.id;
  // ── Route by module ──────────────────────────────────────────────────
  const isDelete = (operation ?? "").toLowerCase() === "delete";
  try {
    if (isDelete && zohoModule === "Contacts") {
      await handleContactDelete(supabase, data, logId);
    } else if (isDelete && zohoModule === "LLP_Creation_Module") {
      await handleLLPDelete(supabase, data);
    } else if (isDelete && zohoModule === "LLP_UnitAllocation_Module") {
      await handleAllocationDelete(supabase, data);
    } else if (zohoModule === "Contacts") {
      await handleContact(supabase, data, modifiedTime);
    } else if (zohoModule === "LLP_Creation_Module") {
      await handleProject(supabase, data);
    } else if (zohoModule === "LLP_UnitAllocation_Module") {
      await handleAllocation(supabase, data);
    } else {
      throw new Error(`unsupported module: ${zohoModule}`);
    }
    const { error: logProcErr } = await supabase.from("webhook_log").update({
      status: "processed",
      processed_at: new Date().toISOString()
    }).eq("id", logId);
    if (logProcErr) console.error(`webhook_log status=processed update failed for ${logId}: ${logProcErr.message}`);
    return jsonResponse(req, {
      status: "ok"
    });
  } catch (err) {
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    const { error: logFailErr } = await supabase.from("webhook_log").update({
      status: "failed",
      error_message: errMsg,
      processed_at: new Date().toISOString()
    }).eq("id", logId);
    if (logFailErr) console.error(`webhook_log status=failed update failed for ${logId}: ${logFailErr.message}`);
    return jsonResponse(req, {
      error: errMsg
    }, {
      status: 500
    });
  }
});
// ── v36: App Access helpers ────────────────────────────────────────────
/// Maps the Zoho App_Access picklist to our states. Returns undefined
/// when the value is missing/unknown so callers can decide the default.
function mapAppAccess(v) {
  const s = (typeof v === "string" ? v : "").trim().toLowerCase();
  if (s === "invite" || s === "invited") return "invited";
  if (s === "hold") return "hold";
  return undefined;
}
async function zohoAccessToken() {
  if (!ZOHO_CLIENT_ID || !ZOHO_CLIENT_SECRET || !ZOHO_REFRESH_TOKEN) return null;
  const r = await fetch(ZOHO_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: ZOHO_REFRESH_TOKEN,
      client_id: ZOHO_CLIENT_ID,
      client_secret: ZOHO_CLIENT_SECRET,
      grant_type: "refresh_token"
    })
  });
  if (!r.ok) return null;
  const j = await r.json();
  return j.access_token ?? null;
}
/// Reads App_Access for a contact. Prefers the webhook payload (if the
/// Deluge function ever starts sending it), else asks the Zoho API.
/// Returns { access, token } — access undefined when unknown.
async function readAppAccess(d) {
  if (d.App_Access !== undefined) return { access: mapAppAccess(d.App_Access), token: null };
  try {
    const token = await zohoAccessToken();
    if (!token) return { access: undefined, token: null };
    const r = await fetch(`${ZOHO_API}/Contacts/${d.id}?fields=App_Access`, {
      headers: { Authorization: `Zoho-oauthtoken ${token}` }
    });
    if (!r.ok) {
      console.error(`[handleContact] Zoho App_Access read failed ${r.status}`);
      return { access: undefined, token };
    }
    const j = await r.json();
    return { access: mapAppAccess(j?.data?.[0]?.App_Access), token };
  } catch (e) {
    console.error("[handleContact] Zoho App_Access read threw", e);
    return { access: undefined, token: null };
  }
}
function escapeHtml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
async function sendWelcomeEmail(to, name) {
  if (!RESEND_API_KEY) {
    console.warn("[welcome] RESEND_API_KEY not set — welcome email NOT sent");
    return false;
  }
  const first = (name || "").trim().split(/\s+/)[0] || "there";
  // Branded welcome (table layout, inline styles, text wordmark so it renders
  // even with images blocked). Preview: supabase/email-templates/welcome.html
  const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<meta name="color-scheme" content="light">
<meta name="supported-color-schemes" content="light">
<title>Welcome to Growize</title>
</head>
<body style="margin:0;padding:0;background-color:#F3F1EA;">
<!-- Preheader (inbox preview line) -->
<div style="display:none;max-height:0;overflow:hidden;mso-hide:all;font-size:1px;line-height:1px;color:#F3F1EA;">Your Growize investor account is ready. Sign in with just your email, no password needed.&#8199;&#65279;&#847;&#8199;&#65279;&#847;&#8199;&#65279;&#847;&#8199;&#65279;&#847;</div>
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" bgcolor="#F3F1EA" style="background-color:#F3F1EA;">
<tr><td align="center" style="padding-top:32px;padding-bottom:32px;padding-left:12px;padding-right:12px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:560px;">

<!-- Header -->
<tr><td bgcolor="#3C5152" style="background-color:#3C5152;border-radius:16px 16px 0 0;padding-top:28px;padding-bottom:24px;padding-left:32px;padding-right:32px;">
  <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr>
    <td style="font-family:Georgia,'Times New Roman',serif;font-size:30px;line-height:32px;font-weight:bold;color:#FFFFFF;letter-spacing:-0.5px;">growize</td>
  </tr><tr>
    <td style="font-family:Arial,Helvetica,sans-serif;font-size:10px;line-height:14px;font-weight:bold;color:#D4AF37;letter-spacing:3px;padding-top:4px;">INVESTOR PORTAL</td>
  </tr></table>
</td></tr>
<tr><td bgcolor="#D4AF37" style="background-color:#D4AF37;height:3px;line-height:3px;font-size:3px;">&nbsp;</td></tr>

<!-- Body -->
<tr><td bgcolor="#FFFFFF" style="background-color:#FFFFFF;padding-top:36px;padding-bottom:8px;padding-left:32px;padding-right:32px;">
  <p style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:24px;line-height:32px;font-weight:bold;color:#0F1A15;">Welcome, ${escapeHtml(first)}</p>
  <p style="margin:0;padding-top:12px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:24px;color:#374151;">Your investor account is ready. Your units, farm progress, payouts and documents are now in one place, updated as your farm grows.</p>

  <!-- Button -->
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" style="margin-top:28px;margin-bottom:8px;"><tr>
    <td align="center" bgcolor="#2E7D6E" style="background-color:#2E7D6E;border-radius:10px;">
      <a href="${APP_WEB_URL}" target="_blank" style="display:inline-block;padding-top:14px;padding-bottom:14px;padding-left:32px;padding-right:32px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:20px;font-weight:bold;color:#FFFFFF;text-decoration:none;border-radius:10px;">Open Growize &rarr;</a>
    </td>
  </tr></table>
</td></tr>

<!-- How to sign in -->
<tr><td bgcolor="#FFFFFF" style="background-color:#FFFFFF;padding-top:24px;padding-bottom:8px;padding-left:32px;padding-right:32px;">
  <p style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:11px;line-height:16px;font-weight:bold;color:#6B7280;letter-spacing:1.5px;">SIGNING IN TAKES A MINUTE</p>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:14px;">
    <tr>
      <td width="36" valign="top" style="padding-bottom:16px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" valign="middle" width="26" height="26" bgcolor="#E9F2EF" style="background-color:#E9F2EF;border-radius:13px;font-family:Arial,Helvetica,sans-serif;font-size:12px;font-weight:bold;color:#2E7D6E;">1</td></tr></table>
      </td>
      <td valign="top" style="padding-bottom:16px;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#374151;">Open <a href="${APP_WEB_URL}" style="color:#2E7D6E;font-weight:bold;text-decoration:none;">${APP_WEB_URL.replace(/^https?:\/\//, "")}</a> on your phone or computer.</td>
    </tr>
    <tr>
      <td width="36" valign="top" style="padding-bottom:16px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" valign="middle" width="26" height="26" bgcolor="#E9F2EF" style="background-color:#E9F2EF;border-radius:13px;font-family:Arial,Helvetica,sans-serif;font-size:12px;font-weight:bold;color:#2E7D6E;">2</td></tr></table>
      </td>
      <td valign="top" style="padding-bottom:16px;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#374151;">Enter your email: <span style="font-weight:bold;color:#0F1A15;">${escapeHtml(to)}</span></td>
    </tr>
    <tr>
      <td width="36" valign="top" style="padding-bottom:8px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0"><tr><td align="center" valign="middle" width="26" height="26" bgcolor="#E9F2EF" style="background-color:#E9F2EF;border-radius:13px;font-family:Arial,Helvetica,sans-serif;font-size:12px;font-weight:bold;color:#2E7D6E;">3</td></tr></table>
      </td>
      <td valign="top" style="padding-bottom:8px;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:22px;color:#374151;">Type the 6-digit code we email you. No password needed.</td>
    </tr>
  </table>
</td></tr>

<!-- Tip -->
<tr><td bgcolor="#FFFFFF" style="background-color:#FFFFFF;padding-top:8px;padding-bottom:28px;padding-left:32px;padding-right:32px;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0"><tr>
    <td bgcolor="#FAFAF7" style="background-color:#FAFAF7;border:1px solid #E1DFC6;border-radius:10px;padding-top:14px;padding-bottom:14px;padding-left:16px;padding-right:16px;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:20px;color:#374151;">
      <span style="font-weight:bold;color:#3C5152;">Tip:</span> on your phone, open the site and choose <span style="font-weight:bold;">Add to Home Screen</span> for one-tap access.
    </td>
  </tr></table>
</td></tr>

<!-- What you'll find -->
<tr><td bgcolor="#FFFFFF" style="background-color:#FFFFFF;padding-top:0;padding-bottom:28px;padding-left:32px;padding-right:32px;border-top:1px solid #EEECE3;">
  <p style="margin:0;padding-top:24px;font-family:Arial,Helvetica,sans-serif;font-size:11px;line-height:16px;font-weight:bold;color:#6B7280;letter-spacing:1.5px;">WHAT YOU'LL FIND INSIDE</p>
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="margin-top:14px;">
    <tr>
      <td width="50%" valign="top" style="padding-right:8px;padding-bottom:16px;font-family:Arial,Helvetica,sans-serif;">
        <p style="margin:0;font-size:14px;line-height:20px;font-weight:bold;color:#0F1A15;">Your units</p>
        <p style="margin:0;font-size:13px;line-height:19px;color:#6B7280;">What you hold, in which farm, and since when.</p>
      </td>
      <td width="50%" valign="top" style="padding-left:8px;padding-bottom:16px;font-family:Arial,Helvetica,sans-serif;">
        <p style="margin:0;font-size:14px;line-height:20px;font-weight:bold;color:#0F1A15;">Farm progress</p>
        <p style="margin:0;font-size:13px;line-height:19px;color:#6B7280;">Milestones, updates and photos from the ground.</p>
      </td>
    </tr>
    <tr>
      <td width="50%" valign="top" style="padding-right:8px;font-family:Arial,Helvetica,sans-serif;">
        <p style="margin:0;font-size:14px;line-height:20px;font-weight:bold;color:#0F1A15;">Payouts</p>
        <p style="margin:0;font-size:13px;line-height:19px;color:#6B7280;">Every payout to your bank, with its reference.</p>
      </td>
      <td width="50%" valign="top" style="padding-left:8px;font-family:Arial,Helvetica,sans-serif;">
        <p style="margin:0;font-size:14px;line-height:20px;font-weight:bold;color:#0F1A15;">Documents</p>
        <p style="margin:0;font-size:13px;line-height:19px;color:#6B7280;">Agreements and certificates, ready to view.</p>
      </td>
    </tr>
  </table>
</td></tr>

<!-- Help -->
<tr><td bgcolor="#FFFFFF" style="background-color:#FFFFFF;border-radius:0 0 16px 16px;padding-top:20px;padding-bottom:28px;padding-left:32px;padding-right:32px;border-top:1px solid #EEECE3;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:20px;color:#374151;">
  Need a hand? Raise a ticket in the app (<span style="font-weight:bold;">Profile &rarr; Assistance</span>) or write to <a href="mailto:${SUPPORT_EMAIL}" style="color:#2E7D6E;text-decoration:none;font-weight:bold;">${SUPPORT_EMAIL}</a>.
  <p style="margin:0;padding-top:16px;color:#0F1A15;">Warm regards,<br><span style="font-weight:bold;">Team Growize</span></p>
</td></tr>

<!-- Footer -->
<tr><td align="center" style="padding-top:20px;padding-left:24px;padding-right:24px;font-family:Arial,Helvetica,sans-serif;font-size:11px;line-height:17px;color:#8A8F87;">
  Growize by Agri Research Labs<br>
  You're receiving this because an investor account was set up for ${escapeHtml(to)}.
</td></tr>

</table>
</td></tr>
</table>
</body>
</html>
`;
  const text = [
    `Welcome, ${first}`,
    ``,
    `Your Growize investor account is ready. Your units, farm progress, payouts and documents are now in one place.`,
    ``,
    `How to sign in:`,
    `1. Open ${APP_WEB_URL} on your phone or computer.`,
    `2. Enter your email: ${to}`,
    `3. Type the 6-digit code we email you. No password needed.`,
    ``,
    `Need a hand? Raise a ticket in the app (Profile > Assistance) or write to ${SUPPORT_EMAIL}.`,
    ``,
    `Warm regards,`,
    `Team Growize`,
    `Growize by Agri Research Labs`,
  ].join("\n");
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, "content-type": "application/json" },
      body: JSON.stringify({ from: RESEND_FROM_EMAIL, to: [to], reply_to: SUPPORT_EMAIL, subject: "Welcome to Growize — your investor account is ready", html, text })
    });
    if (!r.ok) {
      console.error(`[welcome] Resend failed ${r.status}: ${await r.text()}`);
      return false;
    }
    return true;
  } catch (e) {
    console.error("[welcome] Resend threw", e);
    return false;
  }
}
/// Best-effort write-back of the welcome audit fields to Zoho.
async function markWelcomeInZoho(zohoId, token) {
  try {
    const t = token ?? await zohoAccessToken();
    if (!t) return;
    const now = new Date();
    // Zoho datetime format: yyyy-MM-ddTHH:mm:ss+05:30 (IST)
    const ist = new Date(now.getTime() + 5.5 * 3600 * 1000).toISOString().slice(0, 19) + "+05:30";
    const r = await fetch(`${ZOHO_API}/Contacts`, {
      method: "PUT",
      headers: { Authorization: `Zoho-oauthtoken ${t}`, "content-type": "application/json" },
      body: JSON.stringify({ data: [{ id: zohoId, App_Welcome_At: ist, App_Welcome_Channel: "Email" }], trigger: [] })
    });
    if (!r.ok) console.error(`[welcome] Zoho write-back failed ${r.status}: ${await r.text()}`);
  } catch (e) {
    console.error("[welcome] Zoho write-back threw", e);
  }
}
/// Moves an investor to 'invited': unsuspend login, send welcome, record.
async function inviteInvestor(supabase, investorId, email, name, zohoId, token) {
  const { error: unbanErr } = await supabase.auth.admin.updateUserById(investorId, { ban_duration: "none" });
  if (unbanErr) throw new Error(`unsuspend failed for ${investorId}: ${unbanErr.message}`);
  const { error: stErr } = await supabase.from("investors").update({ app_access: "invited", invited_at: new Date().toISOString() }).eq("id", investorId);
  if (stErr) throw new Error(`app_access=invited update failed: ${stErr.message}`);
  const sent = await sendWelcomeEmail(email, name);
  if (sent) await markWelcomeInZoho(zohoId, token);
}
// ── Module handlers ────────────────────────────────────────────────────
async function handleContact(supabase, d, modifiedTime) {
  const fullName = [
    d.First_Name,
    d.Last_Name
  ].filter(Boolean).join(" ").trim();
  const incomingUpdated = modifiedTime ? new Date(modifiedTime) : new Date();
  const { data: cur } = await supabase.from("investors").select("id, updated_at, email, app_access").eq("zoho_contact_id", d.id).maybeSingle();
  if (cur?.updated_at && incomingUpdated <= new Date(cur.updated_at)) {
    return; // stale
  }
  const incomingEmail = d.Email?.trim() || undefined;
  const incomingDob = asDate(d.Date_of_Birth);
  const fields = {
    name: fullName || d.Full_Name || "(unknown)",
    email: incomingEmail,
    phone: d.Mobile || d.Phone,
    salutation: d.Salutation,
    kyc_status: mapKycStatus(d.KYC),
    pan_masked: maskPan(d.PAN_Number),
    bank_account_masked: maskBankAccount(d.Bank_Account_Number),
    bank_ifsc: d.ISFC_Code,
    bank_branch: d.Bank_Branch,
    bank_holder_name: d.Account_Holder_Full_name,
    bank_name: d.Bank_Name,
    date_of_birth: incomingDob,
    aadhaar_masked: maskAadhaar(d.Aadhaar_Number),
    address_line1: d.Mailing_Street,
    city: d.Mailing_City,
    state: d.Mailing_State,
    pincode: d.Mailing_Zip,
    country: d.Mailing_Country,
    unit_allocated: d.Unit_allocated === true,
    payment_received: d.Payment_received === true,
    profile_verified: d.Profile_verified === true,
    agreement_signed: d.Agreement_signed === true,
    fema_applicable: d.FEMA_Applicable === true,
    updated_at: incomingUpdated.toISOString(),
    last_synced_at: new Date().toISOString()
  };
  const { access: wanted, token } = await readAppAccess(d);
  if (!cur) {
    if (!incomingEmail) {
      throw new Error(`cannot auto-onboard contact ${d.id}: missing Email in Zoho payload`);
    }
    // v36: create the login SILENTLY and SUSPENDED — no invite email.
    const { data: created, error: createErr } = await supabase.auth.admin.createUser({
      email: incomingEmail,
      email_confirm: true,
      ban_duration: SUSPENDED,
      user_metadata: {
        source: "zoho-crm-webhook.handleContact",
        zoho_contact_id: d.id
      }
    });
    if (createErr || !created?.user) {
      throw new Error(`createUser failed for ${incomingEmail}: ${createErr?.message ?? "no user returned"}`);
    }
    const newUserId = created.user.id;
    const { error: insErr } = await supabase.from("investors").insert({
      id: newUserId,
      zoho_contact_id: d.id,
      app_access: "hold",
      ...fields
    });
    if (insErr) {
      const { error: cleanupErr } = await supabase.auth.admin.deleteUser(newUserId);
      if (cleanupErr) {
        console.error(`[handleContact] auth user cleanup after insert failure for ${newUserId}: ${cleanupErr.message}`);
      }
      throw new Error(`investors insert (auto-onboard) failed for zoho_contact_id ${d.id}: ${insErr.message}`);
    }
    if (wanted === "invited") {
      await inviteInvestor(supabase, newUserId, incomingEmail, fields.name, d.id, token);
    }
    return;
  }
  const { error: updErr } = await supabase.from("investors").update(fields).eq("zoho_contact_id", d.id);
  if (updErr) {
    throw new Error(`investors update failed: ${updErr.message}`);
  }
  const prevEmail = cur.email?.trim() || undefined;
  if (incomingEmail && prevEmail !== incomingEmail && cur.id) {
    const { error: authErr } = await supabase.auth.admin.updateUserById(cur.id, {
      email: incomingEmail
    });
    if (authErr) {
      console.error(`auth email push failed for ${cur.id}: ${authErr.message}`);
    }
  }
  // v36: App Access transitions for existing investors. Unknown = no change.
  if (wanted === "invited" && cur.app_access !== "invited") {
    await inviteInvestor(supabase, cur.id, incomingEmail ?? prevEmail, fields.name, d.id, token);
  } else if (wanted === "hold" && cur.app_access === "invited") {
    const { error: banErr } = await supabase.auth.admin.updateUserById(cur.id, { ban_duration: SUSPENDED });
    if (banErr) throw new Error(`suspend failed for ${cur.id}: ${banErr.message}`);
    const { error: stErr } = await supabase.from("investors").update({ app_access: "hold" }).eq("id", cur.id);
    if (stErr) throw new Error(`app_access=hold update failed: ${stErr.message}`);
  }
}
async function handleProject(supabase, d) {
  // Zoho LLP_Creation_Module fans out into TWO Supabase rows:
  //   1. `llps` — legal/holding metadata (incorporation, GST, registered address, SPOCs)
  //   2. `projects` — operational record (units, pricing, marketplace, farm location)
  // One LLP can later have multiple projects; the webhook keeps the default
  // 1:1 in sync, admins add additional projects directly in Supabase.
  // 1. Upsert the LLP row, return its id
  const { data: llpRow, error: llpErr } = await supabase.from("llps").upsert({
    zoho_llp_id: d.id,
    name: d.Name,
    llp_status: d.LLP_Status,
    llp_owner: d.LLP_Owner,
    incorporation_no: d.Incorporation_No,
    gst: d.GST,
    pan: d.PAN,
    registered_address_line1: d.registered_address_line1 || d.Address_Line_1,
    registered_city: d.registered_city || d.Address_Line_1_City,
    registered_state: d.registered_state || d.Address_Line_1_State_Province,
    registered_pincode: d.registered_pincode || d.Address_Line_1_Zip_Postal_Code,
    registered_country: d.registered_country || d.Address_Line_1_Country_Region,
    spoc1_name: d.SPOC_1_Full_Name,
    spoc1_phone: d.SPOC_1_Contact_No,
    spoc2_name: d.SPOC_2_Full_Name,
    spoc2_phone: d.SPOC_2_Contact_No,
    updated_at: new Date().toISOString(),
    last_synced_at: new Date().toISOString()
  }, {
    onConflict: "zoho_llp_id",
    ignoreDuplicates: false
  }).select("id").single();
  if (llpErr || !llpRow) {
    throw new Error(`llps upsert failed: ${llpErr?.message}`);
  }
  // 2. Ensure a default project exists under this LLP, then update its
  // operational fields. v32: also include is_listed_in_marketplace in
  // the existing-row read so we can detect transition INTO marketplace
  // for the new_project broadcast.
  const { data: existing } = await supabase.from("projects").select("id, is_listed_in_marketplace").eq("llp_id", llpRow.id).order("updated_at", {
    ascending: true
  }).limit(1).maybeSingle();
  const willBeListed = isListedInMarketplace(d.LLP_Status);
  const wasListed = existing ? existing.is_listed_in_marketplace === true : false;
  const justTransitionedToMarketplace = willBeListed && !wasListed;
  const projectFields = {
    llp_id: llpRow.id,
    name: d.Name,
    tier: d.Tier,
    status: d.LLP_Status,
    city: d.registered_city || d.Address_Line_1_City,
    state: d.registered_state || d.Address_Line_1_State_Province,
    pincode: d.registered_pincode || d.Address_Line_1_Zip_Postal_Code,
    country: d.registered_country || d.Address_Line_1_Country_Region,
    total_units: asNumber(d.Total_Units),
    price_per_unit: asNumber(d.Pet_Unit_Price),
    total_project_cost: asNumber(d.Total_Project_Cost),
    total_ticket_size: asNumber(d.Total_Ticket_Size),
    acreage_acres: asNumber(d.Acreage_Acres),
    annual_yield_pct: parsePercent(d.Annual_Rental_Yield),
    launch_year: asLaunchYearDate(d.Launch_Year),
    insurance_provider: d.Insurance_Provider,
    insurance_policy_no: d.Insurance_Policy_No,
    insurance_expiry_date: asDate(d.Insurance_expiry_date),
    insured_amount: asNumber(d.Insured_Amount),
    is_listed_in_marketplace: willBeListed,
    updated_at: new Date().toISOString(),
    last_synced_at: new Date().toISOString()
  };
  let projectId;
  if (existing?.id) {
    const { error: projUpdErr } = await supabase.from("projects").update(projectFields).eq("id", existing.id);
    if (projUpdErr) throw new Error(`projects update failed: ${projUpdErr.message}`);
    projectId = existing.id;
  } else {
    // Use the LLP's own id as the project id — preserves backfill 1:1
    // mapping from migration 009 and means investor_units rows that
    // came in tied to the LLP id don't need re-pointing.
    const { error: projInsErr } = await supabase.from("projects").insert({
      id: llpRow.id,
      ...projectFields
    });
    if (projInsErr) throw new Error(`projects insert failed: ${projInsErr.message}`);
    projectId = llpRow.id;
  }
  // ── v32 Phase 3 wiring: project_phases fan-out ─────────────────────
  const projectName = d.Name ?? "your project";
  const hasPhaseFields = Object.keys(d).some((k)=>/^phase_\d+_status$/.test(k));
  if (hasPhaseFields) {
    const { data: prevPhasesRaw } = await supabase.from("project_phases").select("phase_name, status").eq("project_id", projectId);
    const prevByName = new Map();
    for (const p of prevPhasesRaw ?? []){
      prevByName.set(p.phase_name, p.status);
    }
    const phaseRows = [];
    for(let i = 1; i <= 10; i++){
      const status = mapPhaseStatus(d[`phase_${i}_status`]);
      const completedAt = asDate(d[`phase_${i}_completed_at`]);
      phaseRows.push({
        project_id: projectId,
        zoho_phase_id: `${d.id}_phase_${i}`,
        phase_name: PHASE_NAMES[i - 1],
        status,
        phase_date: completedAt ?? null,
        sort_order: i,
        updated_at: new Date().toISOString()
      });
    }
    const { error: phaseErr } = await supabase.from("project_phases").upsert(phaseRows, {
      onConflict: "zoho_phase_id"
    });
    if (phaseErr) {
      console.error(`project_phases upsert failed: ${phaseErr.message}`);
    } else {
      for (const row of phaseRows){
        const phaseName = row.phase_name;
        const newStatus = row.status;
        const prev = prevByName.get(phaseName);
        if (newStatus === "current" && prev !== "current") {
          const { error: bcastErr } = await supabase.rpc("broadcast_phase_update_notification", {
            p_project_id: projectId,
            p_phase_name: phaseName,
            p_project_name: projectName
          });
          if (bcastErr) {
            console.error(`phase_update broadcast failed for ${phaseName}: ${bcastErr.message}`);
          }
        }
      }
    }
  }
  if (justTransitionedToMarketplace) {
    const { error: bcastErr } = await supabase.rpc("broadcast_new_project_notification", {
      p_project_id: projectId,
      p_project_name: projectName
    });
    if (bcastErr) {
      console.error(`new_project broadcast failed: ${bcastErr.message}`);
    }
  }
}
async function handleAllocation(supabase, d) {
  // Resolve investor_id and project_id by Zoho IDs.
  const customerZohoId = d.Customer?.id;
  const llpZohoId = d.LLP?.id;
  if (!customerZohoId) throw new Error("missing Customer.id in allocation payload");
  if (!llpZohoId) throw new Error("missing LLP.id in allocation payload");
  const [{ data: inv }, { data: llp }] = await Promise.all([
    supabase.from("investors").select("id").eq("zoho_contact_id", customerZohoId).maybeSingle(),
    supabase.from("llps").select("id").eq("zoho_llp_id", llpZohoId).maybeSingle()
  ]);
  if (!inv?.id) throw new Error(`investor not found for zoho_contact_id ${customerZohoId}`);
  if (!llp?.id) throw new Error(`llp not found for zoho_llp_id ${llpZohoId}`);
  const { data: prj } = await supabase.from("projects").select("id").eq("llp_id", llp.id).order("updated_at", {
    ascending: true
  }).limit(1).maybeSingle();
  if (!prj?.id) throw new Error(`no project under llp ${llp.id} (zoho_llp_id ${llpZohoId})`);
  // Upsert investor_units.
  const { data: unitRow, error: unitErr } = await supabase.from("investor_units").upsert({
    zoho_allocation_id: d.id,
    investor_id: inv.id,
    project_id: prj.id,
    issued_units: asNumber(d.Issued_Units),
    reserved_units: asNumber(d.Reserved_Units),
    unit_price: asNumber(d.Unit_Price),
    capital_invested: asNumber(d.Capital_Invested),
    capital_outstanding: asNumber(d.Capital_Outstanding),
    capital_returns: asNumber(d.Capital_Returns),
    total_amount_receivable: asNumber(d.Total_Amount_Receivable),
    total_amount_received: asNumber(d.Total_Amount_Received),
    token_advance_amount: asNumber(d.Token_Advance_Amount),
    annual_yield_pct: parsePercent(d.Annual_Rental_Yield),
    allocation_status: d.Allocation_Status,
    customer_status: d.Customer_Status,
    investment_date: asDate(d.Investment_Date),
    next_payout_date: asDate(d.Next_Payout),
    last_synced_at: new Date().toISOString()
  }, {
    onConflict: "zoho_allocation_id",
    ignoreDuplicates: false
  }).select("id").single();
  if (unitErr || !unitRow) {
    throw new Error(`investor_units upsert failed: ${unitErr?.message}`);
  }
  const allocationId = unitRow.id;
  const zohoAllocationId = d.id;
  // Unpack payouts from UTR_1..UTR_10 / Amount_1..10 / Date_1..10.
  const payoutRows = [];
  for(let i = 1; i <= 10; i++){
    const utr = i === 1 ? d.UTR_1 || d.UTR : d[`UTR_${i}`];
    const amt = i === 1 ? asNumber(d.Amount_1 || d.Amount) : asNumber(d[`Amount_${i}`]);
    const dt = i === 1 ? d.Date_1 || d.Date : d[`Date_${i}`];
    if (!utr || amt === undefined) continue;
    payoutRows.push({
      investor_id: inv.id,
      project_id: prj.id,
      allocation_id: allocationId,
      source: "crm",
      amount: amt,
      payout_date: asDate(dt) ?? null,
      utr,
      status: "processed",
      idempotency_key: `${zohoAllocationId}_payout_${i}`
    });
  }
  if (payoutRows.length > 0) {
    const { error: payoutErr } = await supabase.from("payouts").upsert(payoutRows, {
      onConflict: "idempotency_key",
      ignoreDuplicates: true
    });
    if (payoutErr) throw new Error(`payouts upsert failed: ${payoutErr.message}`);
    const { data: projInfo } = await supabase.from("projects").select("name").eq("id", prj.id).maybeSingle();
    const { error: notifErr } = await supabase.from("notifications").insert({
      investor_id: inv.id,
      type: "payout",
      title: "Payout processed",
      body: `Your payout for ${projInfo?.name ?? "your project"} has been processed.`,
      metadata: {
        project_id: prj.id,
        payout_count: payoutRows.length,
        allocation_id: allocationId
      }
    });
    if (notifErr) console.error(`notifications insert failed: ${notifErr.message}`);
  }
}
// ── Hard-delete handlers ───────────────────────────────────────────────
async function handleContactDelete(supabase, d, logId) {
  const zohoId = d.id ?? d.Id ?? d.record_id;
  if (!zohoId) {
    throw new Error("missing Contact.id in delete payload");
  }
  const { data: investor, error: lookupErr } = await supabase.from("investors").select("id").eq("zoho_contact_id", zohoId).maybeSingle();
  if (lookupErr) {
    throw new Error(`investors lookup failed: ${lookupErr.message}`);
  }
  if (!investor) {
    return;
  }
  const investorId = investor.id;
  const [unitsRes, payoutsRes, docsRes, notifsRes, bankReqRes, kycResubRes, ticketsRes, exitReqRes] = await Promise.all([
    supabase.from("investor_units").select("id", {
      count: "exact",
      head: true
    }).eq("investor_id", investorId),
    supabase.from("payouts").select("id", {
      count: "exact",
      head: true
    }).eq("investor_id", investorId),
    supabase.from("documents").select("id", {
      count: "exact",
      head: true
    }).eq("investor_id", investorId),
    supabase.from("notifications").select("id", {
      count: "exact",
      head: true
    }).eq("investor_id", investorId),
    supabase.from("bank_change_requests").select("id", {
      count: "exact",
      head: true
    }).eq("investor_id", investorId),
    supabase.from("kyc_resubmissions").select("id", {
      count: "exact",
      head: true
    }).eq("investor_id", investorId),
    supabase.from("support_tickets").select("id", {
      count: "exact",
      head: true
    }).eq("investor_id", investorId),
    supabase.from("exit_requests").select("id, investor_units!inner(investor_id)", {
      count: "exact",
      head: true
    }).eq("investor_units.investor_id", investorId)
  ]);
  const { data: deletedRows, error: delErr } = await supabase.from("investors").delete().eq("zoho_contact_id", zohoId).select("id");
  if (delErr) {
    throw new Error(`investors hard-delete failed: ${delErr.message}`);
  }
  if (deletedRows && deletedRows.length > 0) {
    try {
      const { error: authDelErr } = await supabase.auth.admin.deleteUser(investorId);
      if (authDelErr) {
        console.error(`auth.users hard-delete failed for ${investorId}: ${authDelErr.message}`);
      }
    } catch (authErr) {
      const msg = authErr instanceof Error ? authErr.message : String(authErr);
      console.error(`auth.users hard-delete threw for ${investorId}: ${msg}`);
    }
  }
  const { data: logRow } = await supabase.from("webhook_log").select("payload").eq("id", logId).maybeSingle();
  const basePayload = logRow && typeof logRow.payload === "object" && logRow.payload !== null ? logRow.payload : {};
  const cascadeAudit = {
    deleted_investor_id: investorId,
    cascade_counts: {
      investor_units: unitsRes.count ?? 0,
      payouts: payoutsRes.count ?? 0,
      documents: docsRes.count ?? 0,
      notifications: notifsRes.count ?? 0,
      bank_change_requests: bankReqRes.count ?? 0,
      kyc_resubmissions: kycResubRes.count ?? 0,
      support_tickets: ticketsRes.count ?? 0,
      exit_requests: exitReqRes.count ?? 0
    }
  };
  const { error: auditErr } = await supabase.from("webhook_log").update({
    payload: {
      ...basePayload,
      _cascade_audit: cascadeAudit
    }
  }).eq("id", logId);
  if (auditErr) {
    console.error(`webhook_log cascade-audit update failed for ${logId}: ${auditErr.message}`);
  }
}
async function handleAllocationDelete(supabase, d) {
  const zohoId = d.id ?? d.Id ?? d.record_id;
  if (!zohoId) {
    throw new Error("missing allocation.id in delete payload");
  }
  const { error } = await supabase.from("investor_units").delete().eq("zoho_allocation_id", zohoId);
  if (error) {
    throw new Error(`investor_units hard-delete failed: ${error.message}`);
  }
}
async function handleLLPDelete(supabase, d) {
  const zohoId = d.id ?? d.Id ?? d.record_id;
  if (!zohoId) {
    throw new Error("missing LLP.id in delete payload");
  }
  const { error } = await supabase.from("llps").delete().eq("zoho_llp_id", zohoId);
  if (error) {
    throw new Error(`llps hard-delete failed: ${error.message}`);
  }
}
