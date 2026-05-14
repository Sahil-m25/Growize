// notify-consultation-request — DB-trigger-fired, posts a Slack message
// when a row lands in public.consultation_requests.
//
// Auth: shared-secret header `x-arl-cron-secret` matched against the
//       CRON_SECRET env var. Same pattern as gallery-sync / health-check.
//       Reuses the existing Vault secret so the DB trigger doesn't need
//       a new credential.
//
// Slack URL: read from SLACK_CONSULTATION_WEBHOOK_URL env. When missing
//            we log a warning and return 200 — the function MUST NOT
//            fail the trigger, since pg_net retries every minute and a
//            broken function would blow up the worker queue.
//
// Deploy:
//   supabase functions deploy notify-consultation-request --no-verify-jwt
// Secrets (set via supabase CLI or dashboard):
//   supabase secrets set CRON_SECRET=<value from vault.secrets.cron_secret>
//   supabase secrets set SLACK_CONSULTATION_WEBHOOK_URL=<https://hooks.slack.com/services/...>

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) {
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}

interface TriggerPayload {
  consultation_request_id?: string;
}

interface ConsultationRow {
  id: string;
  user_id: string;
  project_id: string;
  units_requested: number | null;
  message: string | null;
  status: string;
  created_at: string;
}

Deno.serve(async (req: Request) => {
  // ── Shared-secret gate ────────────────────────────────────────────
  const expected = Deno.env.get("CRON_SECRET");
  const got = req.headers.get("x-arl-cron-secret") ?? "";
  if (!expected || !timingSafeEqual(got, expected)) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let body: TriggerPayload;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_body" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const id = body.consultation_request_id;
  if (!id) {
    return new Response(JSON.stringify({ error: "missing_id" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const slackUrl = Deno.env.get("SLACK_CONSULTATION_WEBHOOK_URL");
  if (!slackUrl) {
    console.warn(
      "SLACK_CONSULTATION_WEBHOOK_URL not configured — skipping Slack post for request " +
        id,
    );
    return new Response(
      JSON.stringify({ ok: true, skipped: "no_webhook" }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    );
  }

  const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

  // Look up the row + project name + investor name. Service role
  // bypasses RLS so this works regardless of the original inserter.
  const { data: row, error: rowErr } = await supabase
    .from("consultation_requests")
    .select(
      "id, user_id, project_id, units_requested, message, status, created_at",
    )
    .eq("id", id)
    .maybeSingle();
  if (rowErr || !row) {
    console.error("consultation row lookup failed", { id, err: rowErr });
    return new Response(
      JSON.stringify({ error: "row_not_found", id }),
      { status: 404, headers: { "Content-Type": "application/json" } },
    );
  }

  const consultation = row as ConsultationRow;

  const [{ data: project }, { data: investor }] = await Promise.all([
    supabase
      .from("projects")
      .select("name, tier")
      .eq("id", consultation.project_id)
      .maybeSingle(),
    supabase
      .from("investors")
      .select("full_name, email, phone")
      .eq("user_id", consultation.user_id)
      .maybeSingle(),
  ]);

  const projectName = (project?.name as string | undefined) ?? "Unknown project";
  const projectTier = (project?.tier as string | undefined) ?? "";
  const investorName =
    (investor?.full_name as string | undefined) ?? "Unknown investor";
  const investorEmail = (investor?.email as string | undefined) ?? "";
  const investorPhone = (investor?.phone as string | undefined) ?? "";

  const units = consultation.units_requested ?? 0;
  const msg = (consultation.message ?? "").trim();

  const fields: Array<{ type: string; text: string }> = [
    { type: "mrkdwn", text: `*Investor:*\n${investorName}` },
    { type: "mrkdwn", text: `*Project:*\n${projectName}${projectTier ? ` (${projectTier})` : ""}` },
    { type: "mrkdwn", text: `*Units:*\n${units || "—"}` },
    {
      type: "mrkdwn",
      text: `*Contact:*\n${investorEmail || "—"}${investorPhone ? `\n${investorPhone}` : ""}`,
    },
  ];

  const blocks: unknown[] = [
    {
      type: "header",
      text: { type: "plain_text", text: "New consultation request", emoji: false },
    },
    { type: "section", fields },
  ];
  if (msg.length > 0) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `*Message:*\n${msg}` },
    });
  }
  blocks.push({
    type: "context",
    elements: [
      { type: "mrkdwn", text: `Request ID: \`${consultation.id}\` · ${consultation.created_at}` },
    ],
  });

  const slackRes = await fetch(slackUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      text: `New consultation request from ${investorName} on ${projectName}`,
      blocks,
    }),
  });

  if (!slackRes.ok) {
    const txt = await slackRes.text();
    console.error("Slack post failed", { status: slackRes.status, txt });
    return new Response(
      JSON.stringify({ error: "slack_failed", status: slackRes.status }),
      { status: 502, headers: { "Content-Type": "application/json" } },
    );
  }

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
