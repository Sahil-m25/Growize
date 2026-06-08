// documents-sync — cron-triggered (00:45 UTC / 06:15 IST daily).
//
// Mirrors Zoho CRM attachments into the private `arl-documents` bucket
// and the catalog tables the app reads, so "upload a file in Zoho ->
// it shows up in the app" works without any manual Studio step.
//
//   * PROJECT docs  — non-image attachments on each LLP_Creation_Module
//                     record  ->  arl-documents/project/<project_id>/<file>
//                     + a row in public.project_documents.
//   * PERSONAL docs — attachments on each Contacts record (the investor)
//                     ->  arl-documents/investor/<investor_id>/<file>
//                     + a row in public.documents (visibility='investor').
//
// COMMON-tier docs (company prospectus etc.) have no per-record home in
// Zoho and remain a manual Studio upload — see docs/ops/documents.md.
//
// Idempotent via:
//   * project_documents.zoho_file_id  (UNIQUE, migration 055)
//   * documents.zoho_file_id          (existing column)
// Storage uploads use upsert:false and tolerate "already exists".
//
// Auth: shared-secret header `x-arl-cron-secret` matched against the
//       CRON_SECRET env var — identical to gallery-sync. The pg_cron job
//       (migration 056) sends the same secret read from Vault. Any
//       request without a valid header gets 401.
//
// Storage paths are RLS-aligned (migrations 033 + 047): the storage
// policies key on folder level 1 (`project` / `investor`) and level 2
// (the project_id / the investor's auth uid). investor_id == auth.uid()
// by design, so investor/<investor_id>/<file> is correct.
//
// Deploy:
//   supabase functions deploy documents-sync --no-verify-jwt
// Reuses the secrets already set for gallery-sync (one-time if missing):
//   supabase secrets set CRON_SECRET=<vault.cron_secret value>
//   supabase secrets set ZOHO_CLIENT_ID=... ZOHO_CLIENT_SECRET=... ZOHO_REFRESH_TOKEN=...
//
// Self-contained on purpose (no `_shared/` imports) so the deployed
// source matches this repo file 1:1.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ZOHO_CLIENT_ID = Deno.env.get("ZOHO_CLIENT_ID")!;
const ZOHO_CLIENT_SECRET = Deno.env.get("ZOHO_CLIENT_SECRET")!;
const ZOHO_REFRESH_TOKEN = Deno.env.get("ZOHO_REFRESH_TOKEN")!;

const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({ dsn: SENTRY_EDGE_DSN, tracesSampleRate: 0.1 });
}

const BUCKET = "arl-documents";

// Document file types we mirror. Images are left to gallery-sync.
const DOC_EXT = /\.(pdf|doc|docx|xls|xlsx|ppt|pptx|txt|csv)$/i;

function contentTypeFor(ext: string): string {
  switch (ext.toLowerCase()) {
    case "pdf": return "application/pdf";
    case "doc": return "application/msword";
    case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document";
    case "xls": return "application/vnd.ms-excel";
    case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";
    case "ppt": return "application/vnd.ms-powerpoint";
    case "pptx": return "application/vnd.openxmlformats-officedocument.presentationml.presentation";
    case "txt": return "text/plain";
    case "csv": return "text/csv";
    default: return "application/octet-stream";
  }
}

// Best-effort category for the project-docs UI chip.
function categoryFor(fileName: string): string {
  const n = fileName.toLowerCase();
  if (/agreement|llp|deed|contract/.test(n)) return "legal";
  if (/insurance/.test(n)) return "insurance";
  if (/financial|statement|stmt|balance/.test(n)) return "financial";
  if (/memo|diligence|information|prospectus/.test(n)) return "due_diligence";
  if (/report|update|quarter/.test(n)) return "report";
  return "general";
}

// doc_type for the per-investor documents table.
function docTypeFor(fileName: string): string {
  const n = fileName.toLowerCase();
  if (/kyc|pan|aadhaar|aadhar/.test(n)) return "kyc";
  if (/contract|agreement|nda/.test(n)) return "contract";
  return "other";
}

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

async function getZohoAccessToken(): Promise<string> {
  const response = await fetch("https://accounts.zoho.in/oauth/v2/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      refresh_token: ZOHO_REFRESH_TOKEN,
      client_id: ZOHO_CLIENT_ID,
      client_secret: ZOHO_CLIENT_SECRET,
      grant_type: "refresh_token",
    }),
  });
  const tokenData = await response.json();
  if (!tokenData.access_token) {
    throw new Error(`Zoho token refresh failed: ${JSON.stringify(tokenData)}`);
  }
  return tokenData.access_token as string;
}

interface ZohoAttachment {
  id: string;
  File_Name: string;
}

// deno-lint-ignore no-explicit-any
async function fetchAttachments(
  accessToken: string,
  module: string,
  recordId: string,
): Promise<ZohoAttachment[]> {
  const url = `https://www.zohoapis.in/crm/v3/${module}/${recordId}/Attachments`;
  const resp = await fetch(url, {
    headers: { Authorization: `Zoho-oauthtoken ${accessToken}` },
  });
  if (!resp.ok) {
    console.warn(`Attachments fetch failed (${module}/${recordId}): ${resp.status}`);
    return [];
  }
  const json = await resp.json();
  return (json.data ?? []) as ZohoAttachment[];
}

async function downloadAttachment(
  accessToken: string,
  module: string,
  recordId: string,
  attachmentId: string,
): Promise<ArrayBuffer | null> {
  const url = `https://www.zohoapis.in/crm/v3/${module}/${recordId}/Attachments/${attachmentId}`;
  const resp = await fetch(url, {
    headers: { Authorization: `Zoho-oauthtoken ${accessToken}` },
  });
  if (!resp.ok) {
    console.warn(`Download failed for ${attachmentId}: ${resp.status}`);
    return null;
  }
  return await resp.arrayBuffer();
}

Deno.serve(async (req: Request) => {
  // ── Shared-secret gate ─────────────────────────────────────────────
  const expected = Deno.env.get("CRON_SECRET");
  const got = req.headers.get("x-arl-cron-secret") ?? "";
  if (!expected || !timingSafeEqual(got, expected)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { "Content-Type": "application/json" },
    });
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const runId = crypto.randomUUID();
  const startedAt = new Date().toISOString();

  try {
    const accessToken = await getZohoAccessToken();

    let newProjectDocs = 0;
    let newInvestorDocs = 0;
    const affectedProjectIds: string[] = [];
    const notifyInvestorOfDoc: Array<{ investorId: string; name: string }> = [];

    // ── PART A: project documents (LLP_Creation_Module attachments) ───
    // NOTE: llp_status lives on `llps`, not `projects` (migration 009
    // split LLP from project). Filter via the joined record in JS.
    const { data: projects, error: projError } = await supabase
      .from("projects")
      .select("id, name, llp:llps!inner(zoho_llp_id, llp_status)")
      .not("llp_id", "is", null);
    if (projError) throw new Error(`Failed to fetch projects: ${projError.message}`);

    for (const project of projects ?? []) {
      const llpRel = (project as {
        llp?: { zoho_llp_id?: string; llp_status?: string }
          | Array<{ zoho_llp_id?: string; llp_status?: string }>;
      }).llp;
      const llp = Array.isArray(llpRel) ? llpRel[0] : llpRel;
      const zohoLlpId = llp?.zoho_llp_id;
      if (!zohoLlpId) continue;
      if ((llp?.llp_status ?? "").toLowerCase() === "completed") continue;

      const { data: existing } = await supabase
        .from("project_documents")
        .select("zoho_file_id")
        .eq("project_id", project.id)
        .not("zoho_file_id", "is", null);
      const seen = new Set((existing ?? []).map((r: { zoho_file_id: string }) => r.zoho_file_id));

      const attachments = await fetchAttachments(accessToken, "LLP_Creation_Module", zohoLlpId);
      const fresh = attachments.filter((a) => DOC_EXT.test(a.File_Name) && !seen.has(a.id));

      let order = 0;
      for (const att of fresh) {
        try {
          const buf = await downloadAttachment(accessToken, "LLP_Creation_Module", zohoLlpId, att.id);
          if (!buf) continue;
          const ext = att.File_Name.split(".").pop()?.toLowerCase() ?? "pdf";
          const storagePath = `project/${project.id}/${att.id}.${ext}`;

          const { error: upErr } = await supabase.storage
            .from(BUCKET)
            .upload(storagePath, buf, { contentType: contentTypeFor(ext), upsert: false });
          if (upErr && !upErr.message.includes("already exists")) {
            console.warn(`Upload failed (${att.id}): ${upErr.message}`);
            continue;
          }

          await supabase.from("project_documents").upsert(
            {
              project_id: project.id,
              storage_path: storagePath,
              title: att.File_Name,
              category: categoryFor(att.File_Name),
              zoho_file_id: att.id,
              is_public: false,
              sort_order: order++,
              uploaded_at: new Date().toISOString(),
            },
            { onConflict: "zoho_file_id", ignoreDuplicates: true },
          );
          newProjectDocs++;
        } catch (e) {
          console.warn(`Project doc error ${att.id}:`, e);
        }
      }
      if (fresh.length > 0) affectedProjectIds.push(project.id);
    }

    // ── PART B: personal documents (Contacts attachments) ─────────────
    const { data: investors, error: invError } = await supabase
      .from("investors")
      .select("id, zoho_contact_id, deleted_at")
      .not("zoho_contact_id", "is", null)
      .is("deleted_at", null);
    if (invError) throw new Error(`Failed to fetch investors: ${invError.message}`);

    for (const inv of investors ?? []) {
      const contactId = (inv as { zoho_contact_id?: string }).zoho_contact_id;
      if (!contactId) continue;

      const { data: existing } = await supabase
        .from("documents")
        .select("zoho_file_id")
        .eq("investor_id", inv.id)
        .not("zoho_file_id", "is", null);
      const seen = new Set((existing ?? []).map((r: { zoho_file_id: string }) => r.zoho_file_id));

      const attachments = await fetchAttachments(accessToken, "Contacts", contactId);
      const fresh = attachments.filter((a) => DOC_EXT.test(a.File_Name) && !seen.has(a.id));

      for (const att of fresh) {
        try {
          const buf = await downloadAttachment(accessToken, "Contacts", contactId, att.id);
          if (!buf) continue;
          const ext = att.File_Name.split(".").pop()?.toLowerCase() ?? "pdf";
          const storagePath = `investor/${inv.id}/${att.id}.${ext}`;

          const { error: upErr } = await supabase.storage
            .from(BUCKET)
            .upload(storagePath, buf, { contentType: contentTypeFor(ext), upsert: false });
          if (upErr && !upErr.message.includes("already exists")) {
            console.warn(`Upload failed (${att.id}): ${upErr.message}`);
            continue;
          }

          const { error: insErr } = await supabase.from("documents").insert({
            investor_id: inv.id,
            project_id: null,
            visibility: "investor",
            doc_type: docTypeFor(att.File_Name),
            name: att.File_Name,
            storage_path: storagePath,
            zoho_file_id: att.id,
            file_size_kb: Math.max(1, Math.round(buf.byteLength / 1024)),
            uploaded_at: new Date().toISOString(),
          });
          // 23505 = unique_violation: a concurrent run already inserted it.
          if (insErr && insErr.code !== "23505") {
            console.warn(`Doc insert failed (${att.id}): ${insErr.message}`);
            continue;
          }
          newInvestorDocs++;
          notifyInvestorOfDoc.push({ investorId: inv.id as string, name: att.File_Name });
        } catch (e) {
          console.warn(`Personal doc error ${att.id}:`, e);
        }
      }
    }

    // ── Notifications ─────────────────────────────────────────────────
    // Project docs: notify every investor holding units in the project.
    for (const projectId of affectedProjectIds) {
      const { data: units } = await supabase
        .from("investor_units")
        .select("investor_id")
        .eq("project_id", projectId);
      const { data: projInfo } = await supabase
        .from("projects").select("name").eq("id", projectId).maybeSingle();
      const investorIds = [...new Set((units ?? []).map((u: { investor_id: string }) => u.investor_id))];
      for (const investorId of investorIds) {
        await supabase.from("notifications").insert({
          investor_id: investorId,
          type: "document",
          title: "New project document",
          body: `A new document was added for ${projInfo?.name ?? "your project"}.`,
          metadata: { project_id: projectId },
          created_at: new Date().toISOString(),
        });
      }
    }
    // Personal docs: notify the owning investor.
    for (const d of notifyInvestorOfDoc) {
      await supabase.from("notifications").insert({
        investor_id: d.investorId,
        type: "document",
        title: "New document available",
        body: `${d.name} has been added to your documents.`,
        metadata: {},
        created_at: new Date().toISOString(),
      });
    }

    await supabase.from("webhook_log").insert({
      source: "documents_sync",
      event_type: "daily_sync",
      zoho_record_id: runId,
      idempotency_key: `documents_sync_${startedAt}`,
      payload: {
        projects_scanned: (projects ?? []).length,
        investors_scanned: (investors ?? []).length,
        new_project_docs: newProjectDocs,
        new_investor_docs: newInvestorDocs,
      },
      status: "processed",
      received_at: startedAt,
      processed_at: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({
        status: "ok",
        new_project_docs: newProjectDocs,
        new_investor_docs: newInvestorDocs,
        affected_projects: affectedProjectIds.length,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  } catch (err: unknown) {
    if (SENTRY_EDGE_DSN) await Sentry.captureException(err);
    const errMsg = err instanceof Error ? err.message : String(err);
    await supabase.from("webhook_log").insert({
      source: "documents_sync",
      event_type: "daily_sync",
      zoho_record_id: runId,
      idempotency_key: `documents_sync_${startedAt}_err`,
      payload: { error: errMsg },
      status: "failed",
      error_message: errMsg,
      received_at: startedAt,
    });
    return new Response(JSON.stringify({ error: errMsg }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
