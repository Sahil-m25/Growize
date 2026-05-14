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

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const WEBHOOK_SECRET = Deno.env.get("WEBHOOK_SECRET");

// E.T2: Initialize Sentry if DSN is configured.
const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({
    dsn: SENTRY_EDGE_DSN,
    tracesSampleRate: 0.1,
  });
}

/// Constant-time string compare. Avoids leaking timing info about the secret.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) {
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}

// ── PII masking helpers ────────────────────────────────────────────────
/// PAN: keep first 5, last 1, mask the middle.  RTYUI2468L → RTYUI****L
function maskPan(pan: string | null | undefined): string | null {
  if (!pan) return null;
  const trimmed = String(pan).trim().toUpperCase();
  if (trimmed.length < 6) return trimmed; // too short — store as-is, still likely not real
  return `${trimmed.slice(0, 5)}****${trimmed.slice(-1)}`;
}

/// Bank account: keep last 4 digits.  123456789012 → XXXX-XXXX-9012
function maskBankAccount(acc: string | null | undefined): string | null {
  if (!acc) return null;
  const digits = String(acc).replace(/\D/g, "");
  if (digits.length < 4) return null;
  const last4 = digits.slice(-4);
  return digits.length >= 12 ? `XXXX-XXXX-${last4}` : `XXXX-${last4}`;
}

/// Strip "%" and parse as number, returning null on failure.
function parsePercent(v: unknown): number | null {
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
function asNumber(v: unknown): number | undefined {
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
///
/// We do NOT validate the date format here — Zoho ships ISO-ish strings
/// (`2026-05-08`, `2026-05-08T10:00:00+05:30`) and Postgres handles
/// both. If the upstream value is malformed the upsert will still fail
/// with a parse error naming the column, which is the right blast
/// radius.
function asDate(v: unknown): string | undefined {
  if (v === null || v === undefined) return undefined;
  if (typeof v !== "string") return String(v);
  const trimmed = v.trim();
  return trimmed === "" ? undefined : trimmed;
}

/// Map Zoho CRM `KYC` picklist values to the canonical Supabase enum
/// allowed by `investors_kyc_status_check`
/// (`pending | in_progress | verified | rejected`).
///
/// CRM picklist options Zoho currently exposes (case as picklist-defined):
///   Pending, In Progress, Completed, Verified, Rejected, Not Started.
/// Anything we don't recognise falls back to `pending` so the write
/// never violates the CHECK constraint and silently swallows the
/// update.
/// Zoho's `Launch_Year` is a year-only picklist (e.g. "2026"). The
/// Supabase `projects.launch_year` column is a DATE — passing just
/// "2026" raises `invalid input syntax for type date`. Coerce a bare
/// 4-digit year to Jan 1 of that year; passthrough full ISO dates.
function asLaunchYearDate(v: unknown): string | undefined {
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
function isListedInMarketplace(status: unknown): boolean {
  if (typeof status !== "string") return false;
  const s = status.trim();
  return s === "Open for Reservation" || s === "Open for Issuance";
}

function mapKycStatus(v: unknown): string {
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

/// Returns a deep-cloned copy of the webhook body with sensitive PII
/// fields inside `data` masked. Used for `webhook_log.payload` so the
/// audit log never retains raw PAN, bank account, or Aadhaar numbers.
function sanitizeForLogging(body: unknown): unknown {
  try {
    const clone = JSON.parse(JSON.stringify(body)) as { data?: Record<string, unknown> };
    if (clone && clone.data && typeof clone.data === "object") {
      const d = clone.data;
      if (d.PAN_Number) d.PAN_Number = maskPan(d.PAN_Number as string) ?? "[REDACTED]";
      if (d.Bank_Account_Number) d.Bank_Account_Number = maskBankAccount(d.Bank_Account_Number as string) ?? "[REDACTED]";
      if (d.Aadhaar_Number) d.Aadhaar_Number = "[REDACTED]";
      // Defence in depth — any future field whose name suggests it carries
      // raw account/identity numbers is automatically blanked. Better a
      // false positive in the audit log than a leak.
      for (const key of Object.keys(d)) {
        const k = key.toLowerCase();
        if (k.includes("aadhaar") || k.includes("aadhar")) {
          d[key] = "[REDACTED]";
        }
      }
    }
    return clone;
  } catch {
    // If something is non-serialisable, fall back to a minimal record
    // rather than leaking the original.
    return { _redacted: true, reason: "sanitize_failed" };
  }
}

// ── Types ──────────────────────────────────────────────────────────────
type ZohoModule =
  | "Contacts"
  | "LLP_Creation_Module"
  | "LLP_UnitAllocation_Module";

interface ZohoWebhookBody {
  module?: string;
  operation?: string;
  data?: Record<string, unknown>;
  // Flat-path payloads put record fields directly on the body, so the
  // top level may carry any number of arbitrary string-keyed values.
  [key: string]: unknown;
}

/// Normalises the four accepted request shapes into one envelope:
///
///   1. **Envelope** — `body = { module, operation, data: {...} }`. The
///      shape Zoho Flow / our reconcile job already use. Source label:
///      `envelope`.
///   2. **Flat** — module + operation arrive on the URL as query params
///      (`?module=Contacts&operation=update`); the request body is the
///      record itself with fields at the top level. The shape Zoho's
///      Webhook builder produces with Module Parameters. Source label:
///      `flat`.
///   3. **Mixed** — module/operation present in BOTH query params AND
///      body; data still under `body.data`. We accept it for resilience
///      but query params win. Source label: `mixed`.
///   4. **Query-only** — request body is empty/null and ALL record
///      fields ride on the URL query string alongside module/operation.
///      The shape Zoho's Webhook builder produces when Body Type=None
///      and merge fields are wired through Module Parameters. Source
///      label: `query`.
///
/// Disagreement policy: if module appears in both the query string and
/// the body and the values differ, the query-string value is used. The
/// body value is preserved verbatim in `webhook_log.payload` for audit.
function normaliseRequest(
  url: URL,
  body: ZohoWebhookBody,
): {
  module: string;
  operation: string;
  data: Record<string, unknown>;
  source: "envelope" | "flat" | "mixed" | "query";
} {
  const queryModule = url.searchParams.get("module") ?? undefined;
  const queryOp = url.searchParams.get("operation") ?? undefined;
  const bodyModule = typeof body.module === "string" ? body.module : undefined;
  const bodyOp = typeof body.operation === "string" ? body.operation : undefined;

  const hasEnvelopeData =
    body.data !== undefined &&
    body.data !== null &&
    typeof body.data === "object";

  // Body considered "empty" when it carries no envelope data AND no
  // top-level record fields (after stripping the envelope keys). The
  // query-only fallback only fires in that case so we never overwrite
  // a flat-path body with query params.
  const bodyKeys = Object.keys(body).filter(
    (k) => k !== "module" && k !== "operation" && k !== "data",
  );
  const bodyHasFlatFields = bodyKeys.length > 0;

  let data: Record<string, unknown>;
  let source: "envelope" | "flat" | "mixed" | "query";

  if (hasEnvelopeData) {
    data = body.data as Record<string, unknown>;
    source = queryModule || queryOp ? "mixed" : "envelope";
  } else if (bodyHasFlatFields) {
    // Flat: every body key except the conventional envelope keys is
    // treated as record data. We strip module/operation in case Zoho
    // duplicates them in the body even though it sent query params too.
    data = {};
    for (const k of bodyKeys) data[k] = body[k];
    source = "flat";
  } else {
    // Query-only fallback. Body was {}/null/empty; record fields ride
    // on the URL query string. Copy every query param except the
    // conventional `module` / `operation` slots into data.
    data = {};
    for (const [k, v] of url.searchParams.entries()) {
      if (k === "module" || k === "operation") continue;
      data[k] = v;
    }
    source = "query";
  }

  return {
    module: (queryModule ?? bodyModule ?? "").trim(),
    operation: (queryOp ?? bodyOp ?? "").trim(),
    data,
    source,
  };
}

// ── Handler ────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "method not allowed" }, { status: 405 });
  }

  // Shared-secret gate — constant-time compare.
  const got = req.headers.get("x-arl-webhook-secret") ?? "";
  if (!WEBHOOK_SECRET || !timingSafeEqual(got, WEBHOOK_SECRET)) {
    return jsonResponse(req, { error: "unauthorized" }, { status: 401 });
  }

  // Body parsing is permissive because the query-only path (Zoho
  // Webhook with Body Type=None) sends no body at all. We accept:
  //   - missing/empty body (content-length 0)
  //   - body that fails to parse as JSON
  //   - body that parses to null or a non-object literal
  // …all of which collapse to {}. Real shape validation happens in
  // normaliseRequest + the missing-module/missing-id checks below.
  let rawBody: ZohoWebhookBody;
  try {
    const text = await req.text();
    if (text.trim() === "") {
      rawBody = {};
    } else {
      const parsed = JSON.parse(text);
      rawBody = (parsed && typeof parsed === "object" && !Array.isArray(parsed))
        ? parsed as ZohoWebhookBody
        : {};
    }
  } catch {
    rawBody = {};
  }

  const url = new URL(req.url);
  const { module: zohoModule, operation, data, source: shapeSource } =
    normaliseRequest(url, rawBody);

  if (!zohoModule || typeof data !== "object") {
    return jsonResponse(req, { error: "missing module or data" }, { status: 400 });
  }
  const recordId = (data["id"] ?? "") as string;
  const modifiedTime = (data["Modified_Time"] ?? "") as string;
  if (!recordId) {
    return jsonResponse(req, { error: "missing record id" }, { status: 400 });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const idempotencyKey = `${zohoModule}_${recordId}_${modifiedTime}`;

  // De-dupe — if we've already processed this exact (module, recordId,
  // modifiedTime) tuple, return early. The unique index on
  // webhook_log.idempotency_key is the source of truth.
  const { data: existing } = await supabase
    .from("webhook_log")
    .select("id, status")
    .eq("idempotency_key", idempotencyKey)
    .maybeSingle();
  if (existing && existing.status === "processed") {
    return jsonResponse(req, { status: "duplicate" });
  }

  // ── Log received (with masked payload — Day 1.5 fix) ─────────────────
  // Always log the normalised envelope (data masked) + the inbound
  // shape label. Keeping a fixed shape in webhook_log.payload makes
  // downstream replay / debugging trivial regardless of which path
  // (envelope / flat / mixed) the upstream system used.
  const sanitized = sanitizeForLogging({
    module: zohoModule,
    operation,
    data,
    _shape: shapeSource,
  });
  const { data: logRow, error: logErr } = await supabase
    .from("webhook_log")
    .upsert(
      {
        source: "zoho_crm",
        event_type: operation ? `${zohoModule}.${operation}` : zohoModule,
        zoho_record_id: recordId,
        idempotency_key: idempotencyKey,
        payload: sanitized,
        status: "received",
        received_at: new Date().toISOString(),
      },
      { onConflict: "idempotency_key" },
    )
    .select("id")
    .single();
  if (logErr || !logRow) {
    return jsonResponse(
      req,
      { error: "log insert failed", detail: logErr?.message },
      { status: 500 },
    );
  }
  const logId = logRow.id;

  // ── Route by module ──────────────────────────────────────────────────
  // Soft-delete fan-out: when Zoho fires the delete trigger on a
  // Contact / LLP record, the workflow stamps the `operation` query
  // param (or body field) with `delete`. We mark the corresponding
  // Supabase row's `deleted_at = now()` rather than hard-deleting,
  // so FK chains (investor_units → projects → payouts → documents)
  // keep their parents around for audit + history.
  const isDelete = (operation ?? "").toLowerCase() === "delete";
  try {
    if (isDelete && zohoModule === "Contacts") {
      await handleContactDelete(supabase, data);
    } else if (isDelete && zohoModule === "LLP_Creation_Module") {
      await handleLLPDelete(supabase, data);
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
      processed_at: new Date().toISOString(),
    }).eq("id", logId);
    if (logProcErr) console.error(`webhook_log status=processed update failed for ${logId}: ${logProcErr.message}`);

    return jsonResponse(req, { status: "ok" });
  } catch (err) {
    // E.T2: Capture exception in Sentry if configured.
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    const { error: logFailErr } = await supabase.from("webhook_log").update({
      status: "failed",
      error_message: errMsg,
      processed_at: new Date().toISOString(),
    }).eq("id", logId);
    if (logFailErr) console.error(`webhook_log status=failed update failed for ${logId}: ${logFailErr.message}`);
    return jsonResponse(req, { error: errMsg }, { status: 500 });
  }
});

// ── Module handlers ────────────────────────────────────────────────────

async function handleContact(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
  modifiedTime: string,
) {
  const fullName = [d.First_Name, d.Last_Name].filter(Boolean).join(" ").trim();
  const incomingUpdated = modifiedTime ? new Date(modifiedTime) : new Date();

  // Skip stale updates: if the row already exists and our copy is newer,
  // do nothing. Prevents out-of-order Zoho deliveries from rolling back
  // recent changes.
  const { data: cur } = await supabase
    .from("investors")
    .select("id, updated_at")
    .eq("zoho_contact_id", d.id as string)
    .maybeSingle();
  if (!cur) {
    // No matching investor row — onboard-investor must run first.
    // We silently skip rather than insert (FK to auth.users would fail).
    return;
  }
  if (cur.updated_at && incomingUpdated <= new Date(cur.updated_at)) {
    return; // stale
  }

  const update = {
    name: fullName || (d.Full_Name as string) || "(unknown)",
    email: d.Email as string | undefined,
    phone: (d.Mobile ?? d.Phone) as string | undefined,
    salutation: d.Salutation as string | undefined,
    kyc_status: mapKycStatus(d.KYC),
    pan_masked: maskPan(d.PAN_Number as string | undefined),
    bank_account_masked: maskBankAccount(d.Bank_Account_Number as string | undefined),
    bank_ifsc: d.ISFC_Code as string | undefined,
    bank_branch: d.Bank_Branch as string | undefined,
    bank_holder_name: d.Account_Holder_Full_name as string | undefined,
    bank_name: d.Bank_Name as string | undefined,
    address_line1: d.Mailing_Street as string | undefined,
    city: d.Mailing_City as string | undefined,
    state: d.Mailing_State as string | undefined,
    pincode: d.Mailing_Zip as string | undefined,
    country: d.Mailing_Country as string | undefined,
    unit_allocated: d.Unit_allocated === true,
    payment_received: d.Payment_received === true,
    profile_verified: d.Profile_verified === true,
    agreement_signed: d.Agreement_signed === true,
    fema_applicable: d.FEMA_Applicable === true,
    updated_at: incomingUpdated.toISOString(),
    last_synced_at: new Date().toISOString(),
  };

  // Destructure { error } — bare `await` would swallow PostgREST
  // errors (RLS denial, CHECK violation, FK mismatch) and silently
  // mark the webhook_log row as processed. Throwing surfaces the
  // failure into the route wrapper which then sets status='failed' +
  // error_message, so we notice in Slack / health-check.
  const { error: updErr } = await supabase
    .from("investors")
    .update(update)
    .eq("zoho_contact_id", d.id as string);
  if (updErr) {
    throw new Error(`investors update failed: ${updErr.message}`);
  }
}

async function handleProject(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
) {
  // Zoho LLP_Creation_Module fans out into TWO Supabase rows:
  //   1. `llps` — legal/holding metadata (incorporation, GST, registered address, SPOCs)
  //   2. `projects` — operational record (units, pricing, marketplace, farm location)
  // One LLP can later have multiple projects; the webhook keeps the default
  // 1:1 in sync, admins add additional projects directly in Supabase.

  // 1. Upsert the LLP row, return its id
  const { data: llpRow, error: llpErr } = await supabase
    .from("llps")
    .upsert(
      {
        zoho_llp_id: d.id as string,
        name: d.Name as string,
        llp_status: d.LLP_Status as string | undefined,
        llp_owner: d.LLP_Owner as string | undefined,
        incorporation_no: d.Incorporation_No as string | undefined,
        gst: d.GST as string | undefined,
        pan: d.PAN as string | undefined,
        registered_address_line1: d.Address_Line_1 as string | undefined,
        registered_city: d.Address_Line_1_City as string | undefined,
        registered_state: d.Address_Line_1_State_Province as string | undefined,
        registered_pincode: d.Address_Line_1_Zip_Postal_Code as string | undefined,
        registered_country: d.Address_Line_1_Country_Region as string | undefined,
        spoc1_name: d.SPOC_1_Full_Name as string | undefined,
        spoc1_phone: d.SPOC_1_Contact_No as string | undefined,
        spoc2_name: d.SPOC_2_Full_Name as string | undefined,
        spoc2_phone: d.SPOC_2_Contact_No as string | undefined,
        updated_at: new Date().toISOString(),
        last_synced_at: new Date().toISOString(),
      },
      { onConflict: "zoho_llp_id", ignoreDuplicates: false },
    )
    .select("id")
    .single();

  if (llpErr || !llpRow) {
    throw new Error(`llps upsert failed: ${llpErr?.message}`);
  }

  // 2. Ensure a default project exists under this LLP, then update its
  // operational fields. We key on llp_id (instead of a Zoho id) because
  // one LLP may eventually own multiple projects; the default-project
  // contract is "the one created automatically by the webhook".
  const { data: existing } = await supabase
    .from("projects")
    .select("id")
    .eq("llp_id", llpRow.id)
    .order("updated_at", { ascending: true })
    .limit(1)
    .maybeSingle();

  const projectFields = {
    llp_id: llpRow.id,
    name: d.Name as string,
    tier: d.Tier as string | undefined,
    status: d.LLP_Status as string | undefined,
    city: d.Address_Line_1_City as string | undefined,
    state: d.Address_Line_1_State_Province as string | undefined,
    pincode: d.Address_Line_1_Zip_Postal_Code as string | undefined,
    country: d.Address_Line_1_Country_Region as string | undefined,
    total_units: asNumber(d.Total_Units),
    units_issued: asNumber(d.Units_Issued),
    units_available: asNumber(d.Units_Available_to_Issue),
    price_per_unit: asNumber(d.Pet_Unit_Price),
    total_project_cost: asNumber(d.Total_Project_Cost),
    total_ticket_size: asNumber(d.Total_Ticket_Size),
    acreage_acres: asNumber(d.Acreage_Acres),
    annual_yield_pct: parsePercent(d.Annual_Rental_Yield),
    launch_year: asLaunchYearDate(d.Launch_Year),
    insurance_provider: d.Insurance_Provider as string | undefined,
    insurance_policy_no: d.Insurance_Policy_No as string | undefined,
    insurance_expiry_date: asDate(d.Insurance_expiry_date),
    insured_amount: asNumber(d.Insured_Amount),
    is_listed_in_marketplace: isListedInMarketplace(d.LLP_Status),
    updated_at: new Date().toISOString(),
    last_synced_at: new Date().toISOString(),
  };

  if (existing?.id) {
    const { error: projUpdErr } = await supabase
      .from("projects").update(projectFields).eq("id", existing.id);
    if (projUpdErr) throw new Error(`projects update failed: ${projUpdErr.message}`);
  } else {
    // Use the LLP's own id as the project id — preserves backfill 1:1
    // mapping from migration 009 and means investor_units rows that
    // came in tied to the LLP id don't need re-pointing.
    const { error: projInsErr } = await supabase
      .from("projects").insert({ id: llpRow.id, ...projectFields });
    if (projInsErr) throw new Error(`projects insert failed: ${projInsErr.message}`);
  }
}

async function handleAllocation(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
) {
  // Resolve investor_id and project_id by Zoho IDs.
  const customerZohoId = (d.Customer as { id?: string } | null)?.id;
  const llpZohoId = (d.LLP as { id?: string } | null)?.id;

  if (!customerZohoId) throw new Error("missing Customer.id in allocation payload");
  if (!llpZohoId) throw new Error("missing LLP.id in allocation payload");

  // After the LLP/project split, projects no longer carry zoho_llp_id —
  // it lives on `llps`. Look up the llp first, then its default project
  // (the one created by the webhook's handleProject path).
  const [{ data: inv }, { data: llp }] = await Promise.all([
    supabase.from("investors").select("id").eq("zoho_contact_id", customerZohoId).maybeSingle(),
    supabase.from("llps").select("id").eq("zoho_llp_id", llpZohoId).maybeSingle(),
  ]);
  if (!inv?.id) throw new Error(`investor not found for zoho_contact_id ${customerZohoId}`);
  if (!llp?.id) throw new Error(`llp not found for zoho_llp_id ${llpZohoId}`);

  const { data: prj } = await supabase
    .from("projects")
    .select("id")
    .eq("llp_id", llp.id)
    .order("updated_at", { ascending: true })
    .limit(1)
    .maybeSingle();
  if (!prj?.id) throw new Error(`no project under llp ${llp.id} (zoho_llp_id ${llpZohoId})`);

  // Upsert investor_units.
  const { data: unitRow, error: unitErr } = await supabase
    .from("investor_units")
    .upsert(
      {
        zoho_allocation_id: d.id as string,
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
        allocation_status: d.Allocation_Status as string | undefined,
        customer_status: d.Customer_Status as string | undefined,
        investment_date: asDate(d.Investment_Date),
        next_payout_date: asDate(d.Next_Payout),
        last_synced_at: new Date().toISOString(),
      },
      { onConflict: "zoho_allocation_id", ignoreDuplicates: false },
    )
    .select("id")
    .single();

  if (unitErr || !unitRow) {
    throw new Error(`investor_units upsert failed: ${unitErr?.message}`);
  }

  const allocationId = unitRow.id;
  const zohoAllocationId = d.id as string;

  // Unpack payouts from UTR_1..UTR_10 / Amount_1..10 / Date_1..10.
  const payoutRows: Record<string, unknown>[] = [];
  for (let i = 1; i <= 10; i++) {
    const utr = d[`UTR_${i}`];
    const amt = asNumber(d[`Amount_${i}`]);
    const dt = d[`Date_${i}`];
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
      idempotency_key: `${zohoAllocationId}_payout_${i}`,
    });
  }
  if (payoutRows.length > 0) {
    const { error: payoutErr } = await supabase.from("payouts").upsert(payoutRows, {
      onConflict: "idempotency_key",
      ignoreDuplicates: true,
    });
    if (payoutErr) throw new Error(`payouts upsert failed: ${payoutErr.message}`);

    // Notify investor of new payouts (one notification per webhook,
    // not per payout — investor sees a single "X new payouts" item).
    const { data: projInfo } = await supabase
      .from("projects")
      .select("name")
      .eq("id", prj.id)
      .maybeSingle();

    // Side-effect; log on failure but don't roll back the allocation/payout writes.
    const { error: notifErr } = await supabase.from("notifications").insert({
      investor_id: inv.id,
      type: "payout",
      title: "Payout processed",
      body: `Your payout for ${projInfo?.name ?? "your project"} has been processed.`,
      metadata: {
        project_id: prj.id,
        payout_count: payoutRows.length,
        allocation_id: allocationId,
      },
    });
    if (notifErr) console.error(`notifications insert failed: ${notifErr.message}`);
  }
}

// ── Soft-delete handlers ───────────────────────────────────────────────
// Zoho fires a workflow on Contact / LLP record deletion that POSTs
// here with `operation=delete` and the original record id in the
// payload. We mark `deleted_at = now()` so RLS hides the row from
// the app, FK chains stay intact, and a future restore is trivial
// (UPDATE ... SET deleted_at = NULL). Disabling the auth.users row
// for a deleted contact prevents the now-orphaned investor from
// signing back in.

async function handleContactDelete(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
) {
  const zohoId = (d.id ?? d.Id ?? d.record_id) as string | undefined;
  if (!zohoId) {
    throw new Error("missing Contact.id in delete payload");
  }
  const { data: rows, error } = await supabase
    .from("investors")
    .update({ deleted_at: new Date().toISOString() })
    .eq("zoho_contact_id", zohoId)
    .is("deleted_at", null)
    .select("id");
  if (error) {
    throw new Error(`investors soft-delete failed: ${error.message}`);
  }
  // Ban the auth.users row so any cached refresh token cannot
  // exchange for a new access token. ban_duration is the GoTrue
  // mechanism — Supabase Admin SDK has no `banned: true` flag.
  // 100 years (876000h) is the conventional "indefinite" value.
  for (const row of rows ?? []) {
    const { error: banErr } = await supabase.auth.admin.updateUserById(
      row.id as string,
      { ban_duration: "876000h" } as { ban_duration: string },
    );
    if (banErr) {
      console.error(`auth ban failed for ${row.id}: ${banErr.message}`);
    }
  }
}

async function handleLLPDelete(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
) {
  const zohoId = (d.id ?? d.Id ?? d.record_id) as string | undefined;
  if (!zohoId) {
    throw new Error("missing LLP.id in delete payload");
  }
  const now = new Date().toISOString();

  const { data: llpRows, error: llpErr } = await supabase
    .from("llps")
    .update({ deleted_at: now })
    .eq("zoho_llp_id", zohoId)
    .is("deleted_at", null)
    .select("id");
  if (llpErr) {
    throw new Error(`llps soft-delete failed: ${llpErr.message}`);
  }

  // Cascade: every active project under this LLP gets the same
  // deleted_at stamp. Projects are mirrored 1:1 with LLPs today,
  // but the join keys it generically.
  const llpIds = (llpRows ?? []).map((r) => r.id as string);
  if (llpIds.length > 0) {
    const { error: prjErr } = await supabase
      .from("projects")
      .update({ deleted_at: now })
      .in("llp_id", llpIds)
      .is("deleted_at", null);
    if (prjErr) {
      throw new Error(`projects cascade soft-delete failed: ${prjErr.message}`);
    }
  }
}
