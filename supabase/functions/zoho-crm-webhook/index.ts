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

  // typeof [] === "object" so this predicate already accepts both
  // array- and plain-object-shaped envelope data. The array form is
  // how Zoho's v3 Custom Function webhook envelope ships delete
  // events (and some create/update fan-outs): the body looks like
  //   { "data": [ { "id": "...", ... } ], "module": "...", "operation": "..." }
  // — a one-element array wrapping the record. The plain-object form
  // is what Zoho Flow / our internal reconcile job send. Both are
  // valid; we unwrap arrays to the first element below so downstream
  // handlers see a uniform Record shape.
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
    // Zoho v3 envelope quirk: `data` may be either an array of one
    // record OR a plain object. Delete events in particular ship as
    // `data: [{ id: "..." }]`. Unwrap the array to its first element
    // so the downstream `data["id"]` access works in both shapes.
    // DEF-2026-05-15-11: previously treated `data` as a Record
    // unconditionally, which made array-shaped envelopes fail the
    // missing-record-id check with HTTP 400.
    const envelopeData = body.data;
    data = Array.isArray(envelopeData)
      ? ((envelopeData[0] as Record<string, unknown>) ?? {})
      : (envelopeData as Record<string, unknown>);
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
  // Hard-delete fan-out: when Zoho fires the delete trigger on a
  // Contact / LLP / Allocation record, the workflow stamps the
  // `operation` query param (or body field) with `delete`. We
  // `DELETE FROM` the corresponding Supabase row and rely on the
  // schema's ON DELETE CASCADE FKs to wipe dependents (see each
  // handler for the full cascade map). Replaces the previous
  // `deleted_at = now()` soft-delete behaviour — ops asked for a
  // true hard delete so removed Zoho records don't leave orphans
  // lingering in Supabase. handleContactDelete is the only one
  // that needs the logId, since it also writes cascade-count
  // audit info back to webhook_log.payload.
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

  // Look up the existing investor row by Zoho contact id. v27 silently
  // returned here when no match existed, which left first-seen Zoho
  // Contacts unmirrored and broke downstream allocation lookups
  // ("investor not found for zoho_contact_id …"). v28 (DEF-V27-01)
  // upgrades that no-match branch to a real INSERT — see below.
  const { data: cur } = await supabase
    .from("investors")
    .select("id, updated_at, email")
    .eq("zoho_contact_id", d.id as string)
    .maybeSingle();

  // Stale-event guard: when the row already exists and our copy is
  // older than what's stored, do nothing. Prevents out-of-order Zoho
  // deliveries from rolling back recent changes. Only relevant on
  // the UPDATE path — the INSERT path below by definition isn't stale.
  if (cur?.updated_at && incomingUpdated <= new Date(cur.updated_at)) {
    return; // stale
  }

  const incomingEmail = (d.Email as string | undefined)?.trim() || undefined;
  // DEF-2026-05-15-09: Zoho-side edits to DOB / Aadhaar previously
  // never propagated. Pull both into the investors write map.
  const incomingDob = asDate(d.Date_of_Birth);
  const incomingAadhaar = d.Aadhaar_Number as string | undefined;

  const fields = {
    name: fullName || (d.Full_Name as string) || "(unknown)",
    email: incomingEmail,
    phone: (d.Mobile ?? d.Phone) as string | undefined,
    salutation: d.Salutation as string | undefined,
    kyc_status: mapKycStatus(d.KYC),
    pan_masked: maskPan(d.PAN_Number as string | undefined),
    bank_account_masked: maskBankAccount(d.Bank_Account_Number as string | undefined),
    bank_ifsc: d.ISFC_Code as string | undefined,
    bank_branch: d.Bank_Branch as string | undefined,
    bank_holder_name: d.Account_Holder_Full_name as string | undefined,
    bank_name: d.Bank_Name as string | undefined,
    date_of_birth: incomingDob,
    aadhaar_masked: incomingAadhaar,
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

  if (!cur) {
    // ── v28 DEF-V27-01 fix: auto-onboard first-seen Zoho Contacts ──
    // public.investors.id is `uuid NOT NULL` with no default and FK to
    // auth.users(id) ON DELETE CASCADE, so we can't INSERT directly
    // (no value for `id`) and we can't use gen_random_uuid() (it would
    // trip the FK). Mirror onboard-investor's approach: mint the auth
    // user via admin.inviteUserByEmail (which also emails a magic-link
    // password-setup, same as ops-side onboarding), then INSERT the
    // investors row with that uid as `id`. A returning Zoho update
    // takes the cur-non-null UPDATE branch below.
    if (!incomingEmail) {
      // investors.email is NOT NULL UNIQUE — without it we can't
      // insert. Surface a clear error so ops can fix the Zoho record
      // (or add Email to the workflow payload) and retry.
      throw new Error(
        `cannot auto-onboard contact ${d.id}: missing Email in Zoho payload`,
      );
    }
    const { data: invited, error: inviteErr } = await supabase.auth.admin
      .inviteUserByEmail(incomingEmail, {
        data: {
          source: "zoho-crm-webhook.handleContact",
          zoho_contact_id: d.id as string,
        },
      });
    if (inviteErr || !invited?.user) {
      throw new Error(
        `inviteUserByEmail failed for ${incomingEmail}: ${
          inviteErr?.message ?? "no user returned"
        }`,
      );
    }
    const newUserId = invited.user.id as string;

    const { error: insErr } = await supabase.from("investors").insert({
      id: newUserId,
      zoho_contact_id: d.id as string,
      ...fields,
    });
    if (insErr) {
      // Best-effort cleanup of the auth user we just minted so a
      // future webhook retry isn't blocked by a half-onboarded state.
      // If cleanup itself fails we log + still surface the original
      // insert error — leaving an orphaned auth.users row is the
      // lesser evil vs. silently swallowing the primary failure.
      const { error: cleanupErr } = await supabase.auth.admin.deleteUser(
        newUserId,
      );
      if (cleanupErr) {
        console.error(
          `[handleContact] auth user cleanup after insert failure for ${newUserId}: ${cleanupErr.message}`,
        );
      }
      throw new Error(
        `investors insert (auto-onboard) failed for zoho_contact_id ${d.id}: ${insErr.message}`,
      );
    }
    return;
  }

  // ── Existing investor — UPDATE the full field set ───────────────
  // Destructure { error } — bare `await` would swallow PostgREST
  // errors (RLS denial, CHECK violation, FK mismatch) and silently
  // mark the webhook_log row as processed. Throwing surfaces the
  // failure into the route wrapper which then sets status='failed' +
  // error_message, so we notice in Slack / health-check.
  const { error: updErr } = await supabase
    .from("investors")
    .update(fields)
    .eq("zoho_contact_id", d.id as string);
  if (updErr) {
    throw new Error(`investors update failed: ${updErr.message}`);
  }

  // DEF-2026-05-15-07: keep auth.users.email in sync with the
  // Zoho-authoritative profile email. Without this, ops-side
  // email edits would leave the investor signing in with the
  // stale address. We only push when the value actually changed
  // and is non-empty so we don't trigger unnecessary GoTrue
  // confirmation emails. Side-effect; log on failure but don't
  // roll back the investors update.
  const prevEmail = (cur.email as string | undefined)?.trim() || undefined;
  if (
    incomingEmail
    && prevEmail !== incomingEmail
    && cur.id
  ) {
    const { error: authErr } = await supabase.auth.admin.updateUserById(
      cur.id as string,
      { email: incomingEmail },
    );
    if (authErr) {
      console.error(
        `auth email push failed for ${cur.id}: ${authErr.message}`,
      );
    }
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
    // DEF-2026-05-15-01 + DEF-2026-05-15-05 (migration 046):
    // units_issued + units_available are now derived columns,
    // maintained by the trg_recompute_project_units trigger on
    // investor_units. The webhook no longer writes them — Zoho's
    // Units_Issued / Units_Available_to_Issue are treated as
    // hints, never persisted.
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
  //
  // v28 (DEF-V27-01) note: allocation upsert intentionally does NOT
  // auto-onboard a missing investor or LLP. The Contact + LLP webhooks
  // already self-create their rows on first-seen (Contacts via
  // handleContact's invite path; LLPs via handleProject's existing
  // upsert), so by the time an allocation lands both parents should
  // exist. If they don't, surface a clear error so ops can re-fire
  // the parent webhook in isolation — auto-creating a phantom investor
  // / LLP from an allocation payload would invent rows with missing
  // mandatory fields (email, name, registered address) and trip
  // downstream NOT-NULL constraints.
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
  // Zoho field-naming quirk (DEF-OPS-02): the "UTR 1" picklist on
  // LLP_UnitAllocation_Module ships over the API as `UTR` — no
  // `_1` suffix — and likewise for `Amount` / `Date` for slot 1.
  // Slots 2-10 follow the expected `UTR_2`..`UTR_10` pattern.
  // The `?? d.UTR` fallback below is compensating for that Zoho
  // inconsistency, not a bug — please don't "tidy" it away.
  const payoutRows: Record<string, unknown>[] = [];
  for (let i = 1; i <= 10; i++) {
    const utr = i === 1 ? (d.UTR_1 ?? d.UTR) : d[`UTR_${i}`];
    const amt = i === 1
      ? asNumber(d.Amount_1 ?? d.Amount)
      : asNumber(d[`Amount_${i}`]);
    const dt = i === 1 ? (d.Date_1 ?? d.Date) : d[`Date_${i}`];
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

// ── Hard-delete handlers ───────────────────────────────────────────────
// Zoho fires a workflow on Contact / LLP / Allocation record deletion
// that POSTs here with `operation=delete` and the original record id
// in the payload. We `DELETE FROM` the corresponding Supabase row;
// `ON DELETE CASCADE` on the FKs wipes dependents at the DB layer.
//
// Replaces the previous soft-delete (`deleted_at = now()`) behaviour
// — ops wanted true hard delete so a Zoho cancellation leaves no
// stray rows behind. Cascade maps per handler:
//
//   Contact → investors → CASCADE → bank_change_requests, documents
//     (by investor_id), investor_units (→ exit_requests), kyc_resubmissions,
//     notifications, payouts (by investor_id), support_tickets
//   LLP → llps → CASCADE → projects (→ consultation_requests, crops,
//     gallery_photos, investor_units, payouts, project_phases);
//     documents.project_id and support_tickets.project_id are SET NULL.
//   Allocation → investor_units → CASCADE → exit_requests;
//     payouts.allocation_id is SET NULL.

async function handleContactDelete(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
  logId: string,
) {
  const zohoId = (d.id ?? d.Id ?? d.record_id) as string | undefined;
  if (!zohoId) {
    throw new Error("missing Contact.id in delete payload");
  }

  // Look up the investor first: we need the id for the auth.users
  // hard delete (which happens after the row is gone) and for the
  // pre-delete cascade-count audit. PostgREST never surfaces the
  // CASCADE-deleted children, so we count them up front.
  const { data: investor, error: lookupErr } = await supabase
    .from("investors")
    .select("id")
    .eq("zoho_contact_id", zohoId)
    .maybeSingle();
  if (lookupErr) {
    throw new Error(`investors lookup failed: ${lookupErr.message}`);
  }
  if (!investor) {
    // Nothing to delete — idempotent no-op (e.g. delete already replayed).
    return;
  }
  const investorId = investor.id as string;

  // Capture cascade counts BEFORE the delete so the audit log
  // records how many child rows we wiped. These are sibling tables
  // keyed by investor_id; investor_units' own CASCADE wipes
  // exit_requests (keyed by investor_unit_id, not investor_id, so
  // we count via an embedded filter on the parent).
  const [
    unitsRes,
    payoutsRes,
    docsRes,
    notifsRes,
    bankReqRes,
    kycResubRes,
    ticketsRes,
    exitReqRes,
  ] = await Promise.all([
    supabase.from("investor_units").select("id", { count: "exact", head: true }).eq("investor_id", investorId),
    supabase.from("payouts").select("id", { count: "exact", head: true }).eq("investor_id", investorId),
    supabase.from("documents").select("id", { count: "exact", head: true }).eq("investor_id", investorId),
    supabase.from("notifications").select("id", { count: "exact", head: true }).eq("investor_id", investorId),
    supabase.from("bank_change_requests").select("id", { count: "exact", head: true }).eq("investor_id", investorId),
    supabase.from("kyc_resubmissions").select("id", { count: "exact", head: true }).eq("investor_id", investorId),
    supabase.from("support_tickets").select("id", { count: "exact", head: true }).eq("investor_id", investorId),
    supabase.from("exit_requests").select("id, investor_units!inner(investor_id)", { count: "exact", head: true }).eq("investor_units.investor_id", investorId),
  ]);

  // Hard delete the investor row. CASCADE wipes the child tables
  // counted above. We filter by zoho_contact_id (not id) to keep
  // the delete predicate aligned with how the row was located.
  const { data: deletedRows, error: delErr } = await supabase
    .from("investors")
    .delete()
    .eq("zoho_contact_id", zohoId)
    .select("id");
  if (delErr) {
    throw new Error(`investors hard-delete failed: ${delErr.message}`);
  }

  // Hard delete the auth.users row so the now-orphaned investor
  // can't sign back in. Errors are logged but do NOT fail the
  // function — the investors row going is the primary goal, and
  // leaving an orphaned auth.users row is acceptable fallout.
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

  // Audit: merge cascade counts into webhook_log.payload so a
  // future reader can see exactly what got wiped. Fetch-then-update
  // because PostgREST has no jsonb-merge primitive; the cost is
  // one extra round-trip per delete, which is fine on this hot path.
  const { data: logRow } = await supabase
    .from("webhook_log")
    .select("payload")
    .eq("id", logId)
    .maybeSingle();
  const basePayload = (logRow && typeof logRow.payload === "object" && logRow.payload !== null)
    ? (logRow.payload as Record<string, unknown>)
    : {};
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
      exit_requests: exitReqRes.count ?? 0,
    },
  };
  const { error: auditErr } = await supabase
    .from("webhook_log")
    .update({ payload: { ...basePayload, _cascade_audit: cascadeAudit } })
    .eq("id", logId);
  if (auditErr) {
    console.error(`webhook_log cascade-audit update failed for ${logId}: ${auditErr.message}`);
  }
}

// DEF-2026-05-15-10: hard-delete the matching investor_units row.
// CASCADE wipes exit_requests; payouts.allocation_id is set to NULL
// (per the existing FK rule) so historical payouts survive even
// after the parent allocation goes — they remain tied to the
// investor + project via their other FKs.
async function handleAllocationDelete(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
) {
  const zohoId = (d.id ?? d.Id ?? d.record_id) as string | undefined;
  if (!zohoId) {
    throw new Error("missing allocation.id in delete payload");
  }
  const { error } = await supabase
    .from("investor_units")
    .delete()
    .eq("zoho_allocation_id", zohoId);
  if (error) {
    throw new Error(`investor_units hard-delete failed: ${error.message}`);
  }
  // Parent project's derived units recompute via the
  // trg_recompute_project_units trigger from migration 046.
}

async function handleLLPDelete(
  supabase: ReturnType<typeof createClient>,
  d: Record<string, unknown>,
) {
  const zohoId = (d.id ?? d.Id ?? d.record_id) as string | undefined;
  if (!zohoId) {
    throw new Error("missing LLP.id in delete payload");
  }
  // Hard delete the llps row. ON DELETE CASCADE on projects.llp_id
  // wipes the project row(s) under it, which in turn cascade to
  // consultation_requests, crops, gallery_photos, investor_units,
  // payouts, project_phases. documents.project_id and
  // support_tickets.project_id are SET NULL so investor-side
  // history doesn't break.
  const { error } = await supabase
    .from("llps")
    .delete()
    .eq("zoho_llp_id", zohoId);
  if (error) {
    throw new Error(`llps hard-delete failed: ${error.message}`);
  }
}
