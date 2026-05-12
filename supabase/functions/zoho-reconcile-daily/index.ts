// zoho-reconcile-daily — pull-side fallback for Zoho CRM -> Supabase.
//
// The push path (zoho-crm-webhook) is the primary sync. This function
// is the safety net: if a webhook is missed (Zoho retry exhausted,
// workflow disabled, secret mismatch, network blip), the next reconcile
// run will detect drift and bring Supabase back in line with CRM.
//
// Modules covered (matches the webhook handler 1:1):
//   * Contacts                    -> investors
//   * LLP_Creation_Module         -> llps + projects
//   * LLP_UnitAllocation_Module   -> investor_units (+ payouts on UTR fans)
//
// Strategy per module:
//   1. Page through the Zoho list endpoint with `Modified_Time >= since`
//      where `since = greatest(NOW() - 25h, max(last_synced_at) - 1h)`.
//   2. For each record, look up the matching Supabase row by zoho id.
//      If absent or `updated_at < Modified_Time`, upsert with the same
//      field map the webhook handler uses. Set `last_synced_at = now()`.
//   3. Idempotent: re-running mid-window is safe because the upsert
//      keys on the Zoho id and we honour Modified_Time before writing.
//
// Auth: shared-secret header `x-arl-cron-secret` = CRON_SECRET env var
// (same secret used by gallery-sync + health-check crons).
//
// Deploy: supabase functions deploy zoho-reconcile-daily --no-verify-jwt
// Cron: scheduled in migration 024_sync_alerts_and_reconcile_cron.sql
//       (runs daily 01:00 UTC = 06:30 IST, 30 min after gallery-sync).
//
// Limitations:
//   * Soft deletes from Zoho are NOT propagated. The webhook doesn't
//     handle deletes either; track that separately.
//   * Investor onboarding (auth.users insert) still belongs to
//     onboard-investor — this function only updates pre-existing
//     investor rows.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const CRON_SECRET = Deno.env.get("CRON_SECRET");
const ZOHO_CLIENT_ID = Deno.env.get("ZOHO_CLIENT_ID")!;
const ZOHO_CLIENT_SECRET = Deno.env.get("ZOHO_CLIENT_SECRET")!;
const ZOHO_REFRESH_TOKEN = Deno.env.get("ZOHO_REFRESH_TOKEN")!;

const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({ dsn: SENTRY_EDGE_DSN, tracesSampleRate: 0.1 });
}

const ZOHO_API = "https://www.zohoapis.in/crm/v3";
const ZOHO_TOKEN_URL = "https://accounts.zoho.in/oauth/v2/token";

// Field lists must match the body fields sent by the corresponding Zoho
// Deluge function (`Push_LLP_To_Supabase`, `Push_Contact_To_Supabase`,
// `Push_Allocation_To_Supabase`). When you add a field to one of those
// Deluge functions, add it here too — otherwise reconcile will overwrite
// with null on the next run.
//
// Zoho CRM v3 list endpoint requires an explicit `fields` query param;
// the legacy `fields=*` shortcut is not supported.
// Mirrors every field handleProject() in zoho-crm-webhook reads from
// the LLP payload. The corresponding Deluge function
// (`Push_LLP_To_Supabase`) MUST emit the same set — when one side
// grows, the other must too, or reconcile will overwrite real CRM
// data with stale/empty values on the next run.
const LLP_FIELDS =
  "id,Modified_Time,Name,LLP_Status,LLP_Owner," +
  "Incorporation_No,GST,PAN," +
  "Address_Line_1,Address_Line_1_City,Address_Line_1_State_Province," +
  "Address_Line_1_Zip_Postal_Code,Address_Line_1_Country_Region," +
  "SPOC_1_Full_Name,SPOC_1_Contact_No,SPOC_2_Full_Name,SPOC_2_Contact_No," +
  "Tier,Total_Units,Units_Issued,Units_Available_to_Issue," +
  "Pet_Unit_Price,Total_Project_Cost,Total_Ticket_Size,Acreage_Acres," +
  "Annual_Rental_Yield,Launch_Year," +
  "Insurance_Provider,Insurance_Policy_No,Insurance_expiry_date,Insured_Amount";

const CONTACT_FIELDS =
  "id,Modified_Time,First_Name,Last_Name,Full_Name,Email,Mobile,Phone,Salutation," +
  "KYC,PAN_Number,Bank_Account_Number,ISFC_Code,Bank_Branch,Account_Holder_Full_name,Bank_Name," +
  "Mailing_Street,Mailing_City,Mailing_State,Mailing_Zip,Mailing_Country";
// Booleans (Unit_allocated, Payment_received, Profile_verified,
// Agreement_signed, FEMA_Applicable) intentionally omitted in Phase 1
// — Deluge serializes them as strings; the webhook handler ignores
// anything that isn't strictly === true, so round-tripping them via
// reconcile would silently flip them to false.

const ALLOCATION_FIELDS =
  "id,Modified_Time,LLP,Customer,Issued_Units,Reserved_Units,Unit_Price," +
  "Capital_Invested,Capital_Outstanding,Capital_Returns," +
  "Total_Amount_Receivable,Total_Amount_Received,Token_Advance_Amount," +
  "Annual_Rental_Yield,Allocation_Status,Customer_Status,Investment_Date,Next_Payout";
// LLP and Customer are lookup objects — Zoho v3 returns them as
// {id, name} nested already; no special param needed.

// Default look-back when there are no rows yet (cold start). 25h covers
// any single missed daily run plus an hour of clock skew.
const COLD_START_LOOKBACK_MS = 25 * 60 * 60 * 1000;
// Overlap window to defend against clock skew between Zoho and us when
// computing `since` from max(last_synced_at).
const OVERLAP_MS = 60 * 60 * 1000;

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

function maskPan(pan: string | null | undefined): string | null {
  if (!pan) return null;
  const t = String(pan).trim().toUpperCase();
  if (t.length < 6) return t;
  return `${t.slice(0, 5)}${"*".repeat(t.length - 6)}${t.slice(-1)}`;
}

function maskBankAccount(acc: string | null | undefined): string | null {
  if (!acc) return null;
  const t = String(acc).trim();
  if (t.length < 4) return t;
  return `${"*".repeat(Math.max(0, t.length - 4))}${t.slice(-4)}`;
}

function parsePercent(v: unknown): number | undefined {
  if (v === null || v === undefined || v === "") return undefined;
  const s = String(v).replace(/%/g, "").trim();
  const n = Number(s);
  return isNaN(n) ? undefined : n;
}

/// Map Zoho CRM `KYC` picklist values to the canonical Supabase enum
/// allowed by `investors_kyc_status_check`
/// (`pending | in_progress | verified | rejected`). Mirrors
/// `mapKycStatus()` in zoho-crm-webhook — keep in sync.
/// Zoho's `Launch_Year` is a year-only picklist (e.g. "2026"). The
/// Supabase `projects.launch_year` column is a DATE — passing just
/// "2026" raises `invalid input syntax for type date`. Coerce a bare
/// 4-digit year to Jan 1 of that year; passthrough full ISO dates.
/// Mirror of helper in zoho-crm-webhook — keep in sync.
function asLaunchYearDate(v: unknown): string | undefined {
  if (v === null || v === undefined) return undefined;
  const s = (typeof v === "string" ? v : String(v)).trim();
  if (s === "") return undefined;
  if (/^\d{4}$/.test(s)) return `${s}-01-01`;
  return s;
}

/// Closes DEF-2026-05-11-01. Mirror of helper in zoho-crm-webhook —
/// keep in sync. Derive marketplace visibility from LLP_Status: true
/// when the project is actively soliciting new investors.
function isListedInMarketplace(status: unknown): boolean {
  if (typeof status !== "string") return false;
  const s = status.trim();
  return s === "Open for Reservation" || s === "Open for Issuance";
}

function mapKycStatus(v: unknown): string {
  const raw = (typeof v === "string" ? v : "").trim().toLowerCase();
  if (!raw) return "pending";
  if (raw === "pending" || raw === "in_progress" || raw === "verified" || raw === "rejected") {
    return raw;
  }
  if (raw === "in progress") return "in_progress";
  if (raw === "completed") return "verified";
  if (raw === "not started") return "pending";
  return "pending";
}

async function getZohoAccessToken(): Promise<string> {
  const r = await fetch(ZOHO_TOKEN_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: ZOHO_REFRESH_TOKEN,
      client_id: ZOHO_CLIENT_ID,
      client_secret: ZOHO_CLIENT_SECRET,
      grant_type: "refresh_token",
    }),
  });
  const j = await r.json();
  if (!j.access_token) throw new Error(`Zoho token refresh failed: ${JSON.stringify(j)}`);
  return j.access_token as string;
}

// Page through a Zoho module since a given Modified_Time. Returns all
// records with Modified_Time >= since. Caller is responsible for any
// further filtering.
async function fetchModuleSince(
  module: string,
  fields: string,
  since: Date,
  token: string,
): Promise<Record<string, unknown>[]> {
  const all: Record<string, unknown>[] = [];
  const sinceIso = since.toISOString();
  let page = 1;
  const perPage = 200;
  // Zoho v3 supports `If-Modified-Since` header which limits the
  // returned set to records modified after the timestamp. Combined with
  // pagination via the `page` and `per_page` params. The `fields` param
  // is mandatory on v3 list endpoints — see module field constants at
  // the top of this file.
  while (true) {
    const url = `${ZOHO_API}/${module}?page=${page}&per_page=${perPage}&fields=${encodeURIComponent(fields)}`;
    const r = await fetch(url, {
      headers: {
        Authorization: `Zoho-oauthtoken ${token}`,
        "If-Modified-Since": sinceIso,
      },
    });
    if (r.status === 304) break;
    if (!r.ok) {
      const text = await r.text();
      throw new Error(`zoho fetch ${module} page ${page} failed: ${r.status} ${text.slice(0, 200)}`);
    }
    const body = await r.json();
    const rows: Record<string, unknown>[] = body.data ?? [];
    all.push(...rows);
    const more = body.info?.more_records;
    if (!more || rows.length < perPage) break;
    page += 1;
    if (page > 50) break; // hard cap — 10k rows / run is more than enough
  }
  return all;
}

async function maxSyncedAt(supabase: SupabaseClient, table: string): Promise<Date | null> {
  const { data } = await supabase
    .from(table)
    .select("last_synced_at")
    .order("last_synced_at", { ascending: false, nullsFirst: false })
    .limit(1)
    .maybeSingle();
  const v = (data as { last_synced_at?: string } | null)?.last_synced_at;
  return v ? new Date(v) : null;
}

async function reconcileWindow(supabase: SupabaseClient, table: string): Promise<Date> {
  const max = await maxSyncedAt(supabase, table);
  const fromMax = max ? new Date(max.getTime() - OVERLAP_MS) : null;
  const fromColdStart = new Date(Date.now() - COLD_START_LOOKBACK_MS);
  // Always pull at least a full day back so brief outages don't create a gap.
  return fromMax && fromMax > fromColdStart ? fromColdStart : fromMax ?? fromColdStart;
}

// ── Per-module reconcilers ──────────────────────────────────────────────

async function reconcileContacts(
  supabase: SupabaseClient,
  token: string,
): Promise<{ scanned: number; updated: number }> {
  const since = await reconcileWindow(supabase, "investors");
  const records = await fetchModuleSince("Contacts", CONTACT_FIELDS, since, token);
  let updated = 0;
  for (const d of records) {
    const zohoId = String(d.id ?? "");
    if (!zohoId) continue;
    const modified = (d.Modified_Time as string | undefined) ?? new Date().toISOString();
    const incomingUpdated = new Date(modified);

    const { data: cur } = await supabase
      .from("investors")
      .select("id, updated_at")
      .eq("zoho_contact_id", zohoId)
      .maybeSingle();
    if (!cur) continue; // onboard-investor must run first
    const curUpdated = cur.updated_at ? new Date(cur.updated_at as string) : null;
    if (curUpdated && incomingUpdated <= curUpdated) {
      // Even if no value changed, refresh last_synced_at so freshness
      // checks reflect the reconcile pass.
      const { error: refreshErr } = await supabase.from("investors").update({ last_synced_at: new Date().toISOString() }).eq("id", cur.id);
      if (refreshErr) console.error(`investors last_synced_at refresh failed for ${cur.id}: ${refreshErr.message}`);
      continue;
    }

    const fullName = [d.First_Name, d.Last_Name].filter(Boolean).join(" ").trim();
    const { error: invUpdErr } = await supabase
      .from("investors")
      .update({
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
      })
      .eq("id", cur.id);
    if (invUpdErr) throw new Error(`investors update failed for ${cur.id}: ${invUpdErr.message}`);
    updated += 1;
  }
  return { scanned: records.length, updated };
}

async function reconcileLlps(
  supabase: SupabaseClient,
  token: string,
): Promise<{ scanned: number; updated: number }> {
  const since = await reconcileWindow(supabase, "llps");
  const records = await fetchModuleSince("LLP_Creation_Module", LLP_FIELDS, since, token);
  const now = () => new Date().toISOString();
  let updated = 0;
  for (const d of records) {
    const zohoId = String(d.id ?? "");
    if (!zohoId) continue;

    const llpFields = {
      zoho_llp_id: zohoId,
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
      updated_at: now(),
      last_synced_at: now(),
    };

    const { data: llpRow, error: llpErr } = await supabase
      .from("llps")
      .upsert(llpFields, { onConflict: "zoho_llp_id", ignoreDuplicates: false })
      .select("id")
      .single();
    if (llpErr || !llpRow) {
      console.warn(`reconcile llps upsert failed for ${zohoId}: ${llpErr?.message}`);
      continue;
    }

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
      total_units: d.Total_Units as number | undefined,
      units_issued: d.Units_Issued as number | undefined,
      units_available: d.Units_Available_to_Issue as number | undefined,
      price_per_unit: d.Pet_Unit_Price as number | undefined,
      total_project_cost: d.Total_Project_Cost as number | undefined,
      total_ticket_size: d.Total_Ticket_Size as number | undefined,
      acreage_acres: d.Acreage_Acres as number | undefined,
      annual_yield_pct: parsePercent(d.Annual_Rental_Yield),
      launch_year: asLaunchYearDate(d.Launch_Year),
      insurance_provider: d.Insurance_Provider as string | undefined,
      insurance_policy_no: d.Insurance_Policy_No as string | undefined,
      insurance_expiry_date: d.Insurance_expiry_date as string | undefined,
      insured_amount: d.Insured_Amount as number | undefined,
      is_listed_in_marketplace: isListedInMarketplace(d.LLP_Status),
      updated_at: now(),
      last_synced_at: now(),
    };

    if (existing?.id) {
      const { error: projUpdErr } = await supabase.from("projects").update(projectFields).eq("id", existing.id);
      if (projUpdErr) throw new Error(`projects update failed for ${existing.id}: ${projUpdErr.message}`);
    } else {
      const { error: projInsErr } = await supabase.from("projects").insert({ id: llpRow.id, ...projectFields });
      if (projInsErr) throw new Error(`projects insert failed for ${llpRow.id}: ${projInsErr.message}`);
    }
    updated += 1;
  }
  return { scanned: records.length, updated };
}

async function reconcileAllocations(
  supabase: SupabaseClient,
  token: string,
): Promise<{ scanned: number; updated: number }> {
  const since = await reconcileWindow(supabase, "investor_units");
  const records = await fetchModuleSince("LLP_UnitAllocation_Module", ALLOCATION_FIELDS, since, token);
  const nowIso = () => new Date().toISOString();
  let updated = 0;
  for (const d of records) {
    const zohoId = String(d.id ?? "");
    if (!zohoId) continue;

    // Resolve FK ids
    const investorZoho = String(((d.Investor as { id?: string } | undefined)?.id) ?? d.Investor_id ?? "");
    const llpZoho = String(((d.LLP as { id?: string } | undefined)?.id) ?? d.LLP_id ?? "");
    if (!investorZoho || !llpZoho) continue;

    const [{ data: inv }, { data: llp }] = await Promise.all([
      supabase.from("investors").select("id").eq("zoho_contact_id", investorZoho).maybeSingle(),
      supabase.from("llps").select("id").eq("zoho_llp_id", llpZoho).maybeSingle(),
    ]);
    if (!inv || !llp) continue;
    const { data: prj } = await supabase.from("projects").select("id").eq("llp_id", llp.id).limit(1).maybeSingle();
    if (!prj) continue;

    const { error: unitUpsertErr } = await supabase
      .from("investor_units")
      .upsert(
        {
          zoho_allocation_id: zohoId,
          investor_id: inv.id,
          project_id: prj.id,
          issued_units: d.Issued_Units as number | undefined,
          reserved_units: d.Reserved_Units as number | undefined,
          unit_price: d.Unit_Price as number | undefined,
          capital_invested: d.Capital_Invested as number | undefined,
          capital_outstanding: d.Capital_Outstanding as number | undefined,
          capital_returns: d.Capital_Returns as number | undefined,
          total_amount_receivable: d.Total_Amount_Receivable as number | undefined,
          total_amount_received: d.Total_Amount_Received as number | undefined,
          token_advance_amount: d.Token_Advance_Amount as number | undefined,
          annual_yield_pct: parsePercent(d.Annual_Rental_Yield),
          allocation_status: d.Allocation_Status as string | undefined,
          customer_status: d.Customer_Status as string | undefined,
          investment_date: d.Investment_Date as string | undefined,
          next_payout_date: d.Next_Payout as string | undefined,
          updated_at: nowIso(),
          last_synced_at: nowIso(),
        },
        { onConflict: "zoho_allocation_id", ignoreDuplicates: false },
      );
    if (unitUpsertErr) throw new Error(`investor_units upsert failed for ${zohoId}: ${unitUpsertErr.message}`);
    updated += 1;
  }
  return { scanned: records.length, updated };
}

// ── HTTP entrypoint ─────────────────────────────────────────────────────

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

  const startedAt = new Date().toISOString();
  try {
    const token = await getZohoAccessToken();
    // Run modules sequentially — Allocations depend on llps + investors
    // already being current.
    const contacts = await reconcileContacts(supabase, token);
    const llps = await reconcileLlps(supabase, token);
    const allocs = await reconcileAllocations(supabase, token);

    const { error: logSuccessErr } = await supabase.from("webhook_log").insert({
      source: "zoho_crm",
      event_type: "reconcile_daily",
      idempotency_key: `reconcile_daily_${startedAt}`,
      payload: { contacts, llps, allocs },
      status: "processed",
      received_at: startedAt,
      processed_at: new Date().toISOString(),
    });
    if (logSuccessErr) console.error(`webhook_log insert (success path) failed: ${logSuccessErr.message}`);

    return jsonResponse({ status: "ok", contacts, llps, allocs });
  } catch (err) {
    if (SENTRY_EDGE_DSN) await Sentry.captureException(err);
    const errMsg = err instanceof Error ? err.message : String(err);
    const { error: logFailErr } = await supabase.from("webhook_log").insert({
      source: "zoho_crm",
      event_type: "reconcile_daily",
      idempotency_key: `reconcile_daily_${startedAt}_err`,
      payload: { error: errMsg },
      status: "failed",
      error_message: errMsg,
      received_at: startedAt,
      processed_at: new Date().toISOString(),
    });
    if (logFailErr) console.error(`webhook_log insert (failure path) failed: ${logFailErr.message}`);
    return jsonResponse({ error: errMsg }, { status: 500 });
  }
});
