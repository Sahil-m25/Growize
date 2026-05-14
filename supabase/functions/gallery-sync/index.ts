// gallery-sync — P1, cron-triggered (06:00 IST daily).
//
// Polls Zoho CRM for new attachments on each LLP_Creation_Module record
// and copies them into the arl-gallery Supabase Storage bucket.
// Idempotent via gallery_photos.zoho_file_id UNIQUE.
//
// Auth: shared-secret header `x-arl-cron-secret` matched against the
//       CRON_SECRET env var. The cron job (see migration
//       016_gallery_sync_cron_shared_secret) reads the same secret from
//       Vault and sends it on each call. Any request without a valid
//       header gets 401 — the function is no longer publicly invokable.
//
// Deploy:
//   supabase functions deploy gallery-sync --no-verify-jwt
// Set secret (one-time, on first deploy):
//   supabase secrets set CRON_SECRET=<value from vault.secrets.cron_secret>
//
// Note: this file is intentionally self-contained (no `_shared/` imports)
// so the deployed source matches this repo file 1:1. If you reorganise
// shared helpers into _shared/, redeploy this function and reconcile.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ZOHO_CLIENT_ID = Deno.env.get("ZOHO_CLIENT_ID")!;
const ZOHO_CLIENT_SECRET = Deno.env.get("ZOHO_CLIENT_SECRET")!;
const ZOHO_REFRESH_TOKEN = Deno.env.get("ZOHO_REFRESH_TOKEN")!;

// E.T2: Initialize Sentry if DSN is configured.
const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({
    dsn: SENTRY_EDGE_DSN,
    tracesSampleRate: 0.1,
  });
};

/// Constant-time string compare. Avoids leaking timing information about
/// the secret via early-exit on mismatch. Lengths still leak; both sides
/// use the same fixed-length hex secret so that's acceptable.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) {
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}

// Refresh Zoho access token using refresh token
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

Deno.serve(async (req: Request) => {
  // ── Shared-secret gate ─────────────────────────────────────────────
  // verify_jwt is false for this function (cron has no JWT), so we
  // enforce auth ourselves. Reject anything without a matching secret.
  const expected = Deno.env.get("CRON_SECRET");
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

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const runId = crypto.randomUUID();
  const startedAt = new Date().toISOString();

  try {
    // Get Zoho access token
    const accessToken = await getZohoAccessToken();

    // 1. Fetch all active projects (zoho_llp_id lives on llps after the LLP/project split)
    const { data: projects, error: projError } = await supabase
      .from("projects")
      .select("id, name, llp_status, llp:llps!inner(zoho_llp_id)")
      .neq("llp_status", "completed")
      .not("llp_id", "is", null);

    if (projError) throw new Error(`Failed to fetch projects: ${projError.message}`);
    if (!projects || projects.length === 0) {
      return new Response(JSON.stringify({ status: "ok", message: "No active projects" }), {
        status: 200,
        headers: { "Content-Type": "application/json" },
      });
    }

    let totalNewPhotos = 0;
    const affectedProjectIds: string[] = [];

    for (const project of projects) {
      // PostgREST returns embedded relations as object or array depending on cardinality; normalise.
      const llpRel = (project as { llp?: { zoho_llp_id?: string } | Array<{ zoho_llp_id?: string }> }).llp;
      const zohoLlpId = Array.isArray(llpRel) ? llpRel[0]?.zoho_llp_id : llpRel?.zoho_llp_id;
      if (!zohoLlpId) continue;

      // 2. Fetch existing gallery photo IDs for this project
      const { data: existingPhotos } = await supabase
        .from("gallery_photos")
        .select("zoho_file_id")
        .eq("project_id", project.id);

      const existingFileIds = new Set((existingPhotos ?? []).map((p: { zoho_file_id: string }) => p.zoho_file_id));

      // 3. Fetch attachments from Zoho CRM
      const attachmentsUrl = `https://www.zohoapis.in/crm/v3/LLP_Creation_Module/${zohoLlpId}/Attachments`;
      const attachResp = await fetch(attachmentsUrl, {
        headers: { Authorization: `Zoho-oauthtoken ${accessToken}` },
      });

      if (!attachResp.ok) {
        console.warn(`Failed to fetch attachments for project ${zohoLlpId}: ${attachResp.status}`);
        continue;
      }

      const attachData = await attachResp.json();
      const attachments: Array<{ id: string; File_Name: string; $download_url?: string }> =
        attachData.data ?? [];

      // 4. Filter only image attachments not yet synced
      const newAttachments = attachments.filter((a) => {
        const isImage = /\.(jpg|jpeg|png|webp)$/i.test(a.File_Name);
        return isImage && !existingFileIds.has(a.id);
      });

      let projectNewCount = 0;

      for (const attachment of newAttachments) {
        try {
          // 5. Download attachment from Zoho
          const downloadUrl = `https://www.zohoapis.in/crm/v3/LLP_Creation_Module/${zohoLlpId}/Attachments/${attachment.id}`;
          const fileResp = await fetch(downloadUrl, {
            headers: { Authorization: `Zoho-oauthtoken ${accessToken}` },
          });

          if (!fileResp.ok) {
            console.warn(`Download failed for ${attachment.id}: ${fileResp.status}`);
            continue;
          }

          const fileBuffer = await fileResp.arrayBuffer();
          const ext = attachment.File_Name.split(".").pop()?.toLowerCase() ?? "jpg";
          const storagePath = `gallery/${project.id}/${attachment.id}.${ext}`;

          // 6. Upload to Supabase Storage
          const { error: uploadError } = await supabase.storage
            .from("arl-gallery")
            .upload(storagePath, fileBuffer, {
              contentType: `image/${ext === "jpg" ? "jpeg" : ext}`,
              upsert: false,
            });

          if (uploadError && !uploadError.message.includes("already exists")) {
            console.warn(`Upload failed for ${attachment.id}: ${uploadError.message}`);
            continue;
          }

          // 7. Record in gallery_photos
          await supabase.from("gallery_photos").upsert(
            {
              project_id: project.id,
              storage_path: storagePath,
              zoho_file_id: attachment.id,
              caption: attachment.File_Name,
              uploaded_at: new Date().toISOString(),
            },
            { onConflict: "zoho_file_id", ignoreDuplicates: true }
          );

          projectNewCount++;
        } catch (photoErr) {
          console.warn(`Error processing attachment ${attachment.id}:`, photoErr);
        }
      }

      if (projectNewCount > 0) {
        totalNewPhotos += projectNewCount;
        affectedProjectIds.push(project.id);
      }
    }

    // 8. Send notifications to investors for affected projects
    for (const projectId of affectedProjectIds) {
      const { data: units } = await supabase
        .from("investor_units")
        .select("investor_id")
        .eq("project_id", projectId);

      const { data: projInfo } = await supabase
        .from("projects")
        .select("name")
        .eq("id", projectId)
        .maybeSingle();

      const uniqueInvestors = [...new Set((units ?? []).map((u: { investor_id: string }) => u.investor_id))];

      for (const investorId of uniqueInvestors) {
        await supabase.from("notifications").insert({
          investor_id: investorId,
          type: "photo",
          title: "New farm photos added",
          body: `New photos have been uploaded for ${projInfo?.name ?? "your project"}.`,
          metadata: { project_id: projectId },
          created_at: new Date().toISOString(),
        });
      }
    }

    // 9. Log sync result
    await supabase.from("webhook_log").insert({
      source: "gallery_sync",
      event_type: "daily_sync",
      zoho_record_id: runId,
      idempotency_key: `gallery_sync_${startedAt}`,
      payload: { projects_scanned: projects.length, new_photos: totalNewPhotos },
      status: "processed",
      received_at: startedAt,
      processed_at: new Date().toISOString(),
    });

    return new Response(
      JSON.stringify({
        status: "ok",
        projects_scanned: projects.length,
        new_photos: totalNewPhotos,
        affected_projects: affectedProjectIds.length,
      }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err: unknown) {
    // E.T2: Capture exception in Sentry if configured.
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    await supabase.from("webhook_log").insert({
      source: "gallery_sync",
      event_type: "daily_sync",
      zoho_record_id: runId,
      idempotency_key: `gallery_sync_${startedAt}_err`,
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
