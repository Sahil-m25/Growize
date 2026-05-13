// onboard-investor — P0
//
// Called by ARL staff (Postman, Studio, future admin tool) to invite a
// new investor. Validates an admin shared-secret header, sends a Supabase
// magic-link "set up your password" email, and inserts the matching
// `investors` row keyed to the new auth.users.id.
//
// Email validation (DEF-2026-05-11-02): Supabase Auth rejects RFC 6761
// reserved TLDs (.test, .example, .invalid, .localhost) — the call fails
// with `Email "<addr>" is invalid` from inviteUserByEmail. For UAT/QA
// fixtures use a real domain (e.g. @agresearchlabs.com); the magic-link
// email won't be deliverable but the auth user + investors row are
// created normally.
//
// Auth: X-ARL-Admin-Secret header must equal the ADMIN_SECRET env var.
//       Compared in constant time to avoid leaking the secret via timing.
//
// Deploy: supabase functions deploy onboard-investor --no-verify-jwt
// Set secret: supabase secrets set ADMIN_SECRET=<long random hex>
//
// CORS helpers (corsHeaders / preflight / jsonResponse) are imported
// from `../_shared/cors.ts` — origin-aware allow-list, replaces the
// pre-launch `*` posture per audit S-005
// (docs/security_audit_2026-05-13.md). Each jsonResponse call passes
// `req` so the helper can echo the matched origin from
// APP_ALLOWED_ORIGINS instead of a wildcard.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import * as Sentry from "https://deno.land/x/sentry@8.0.0-rc.3/index.mjs";
import { jsonResponse, preflight } from "../_shared/cors.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ADMIN_SECRET = Deno.env.get("ADMIN_SECRET");

// E.T2: Initialize Sentry if DSN is configured.
const SENTRY_EDGE_DSN = Deno.env.get("SENTRY_EDGE_DSN");
if (SENTRY_EDGE_DSN) {
  await Sentry.init({
    dsn: SENTRY_EDGE_DSN,
    tracesSampleRate: 0.1,
  });
}

// Investors are bounced into the Flutter app via the registered Android
// scheme `com.arl.app://auth` (see AndroidManifest.xml + config.toml's
// additional_redirect_urls). Web build can be added later by extending
// additional_redirect_urls and switching this URL on a build flag.
const APP_DEEP_LINK = "com.arl.app://auth";

/// Constant-time string compare. Avoids leaking timing info about the secret.
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) {
    r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return r === 0;
}

interface OnboardBody {
  email: string;
  name: string;
  arl_id: string;
  zoho_contact_id?: string;
  phone?: string;
  salutation?: string;
}

Deno.serve(async (req: Request) => {
  const pf = preflight(req);
  if (pf) return pf;
  if (req.method !== "POST") {
    return jsonResponse(req, { error: "method not allowed" }, { status: 405 });
  }

  try {
    // ── Admin-secret gate ─────────────────────────────────────────────
    const got = req.headers.get("x-arl-admin-secret") ?? "";
    if (!ADMIN_SECRET || !timingSafeEqual(got, ADMIN_SECRET)) {
      return jsonResponse(req, { error: "unauthorized" }, { status: 401 });
    }

    // ── Parse + validate body ─────────────────────────────────────────
    let body: OnboardBody;
    try {
      body = await req.json();
    } catch {
      return jsonResponse(req, { error: "invalid json" }, { status: 400 });
    }
    const { email, name, arl_id, zoho_contact_id, phone, salutation } = body;
    if (!email || !name || !arl_id) {
      return jsonResponse(
        req,
        { error: "email, name, arl_id are required" },
        { status: 400 },
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // ── Existing investor? ────────────────────────────────────────────
    const { data: existing } = await supabase
      .from("investors")
      .select("id, email")
      .eq("email", email)
      .maybeSingle();
    if (existing) {
      return jsonResponse(
        req,
        { error: "investor already exists", investor_id: existing.id },
        { status: 409 },
      );
    }

    // ── Send invite (creates auth.users row + emails password-set link) ─
    // redirectTo points at the Flutter app's deep-link scheme so opening
    // the email on Android lands the investor inside the app.
    const { data: invited, error: inviteErr } = await supabase.auth.admin
      .inviteUserByEmail(email, {
        data: { arl_id, name },
        redirectTo: APP_DEEP_LINK,
      });
    if (inviteErr || !invited?.user) {
      return jsonResponse(
        req,
        { error: "invite failed", detail: inviteErr?.message },
        { status: 500 },
      );
    }

    // ── Insert matching investors row (id = auth.users.id) ────────────
    const { error: insertErr } = await supabase.from("investors").insert({
      id: invited.user.id,
      email,
      name,
      arl_id,
      zoho_contact_id: zoho_contact_id ?? null,
      phone: phone ?? null,
      salutation: salutation ?? null,
      kyc_status: "pending",
      onboarded_at: new Date().toISOString(),
    });
    if (insertErr) {
      // Auth user exists but our row failed — best-effort cleanup so
      // the next attempt with the same email isn't blocked.
      await supabase.auth.admin.deleteUser(invited.user.id).catch(() => {});
      return jsonResponse(
        req,
        { error: "investor insert failed", detail: insertErr.message },
        { status: 500 },
      );
    }

    return jsonResponse(req, {
      investor_id: invited.user.id,
      arl_id,
      message: "Invite sent — investor will receive a password-setup email",
    });
  } catch (err: unknown) {
    // E.T2: Capture exception in Sentry if configured.
    if (SENTRY_EDGE_DSN) {
      await Sentry.captureException(err);
    }
    const errMsg = err instanceof Error ? err.message : String(err);
    return jsonResponse(req, { error: errMsg }, { status: 500 });
  }
});
