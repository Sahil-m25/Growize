// request-auth-email
// OTP entry point for the Growize app. Looks up the investor in public.investors
// (so randoms can't enumerate), then asks Supabase Auth to send a 6-digit code.
//
// Body shape:  { "email": "x@y.com" }   OR   { "phone": "+919876500001" }
//
// Returns the SAME generic response regardless of whether the contact exists,
// so attackers can't tell which emails / phones are registered.
//
// Email is enabled today. Phone support is wired but no-ops until the project
// has an SMS provider configured (Twilio / MSG91 / etc).
//
// Version 5 (2026-05-25): Source-synced with deployed version. The Magic Link
// email template must render `{{ .Token }}` (the 6-digit code), NOT
// `{{ .ConfirmationURL }}` — that's a Dashboard-only setting under
// Authentication → Email Templates → Magic Link. This function deliberately
// omits `emailRedirectTo` / `redirect_to` so Supabase issues a pure-token
// OTP rather than a magic-link URL.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function genericReply(channel: "email" | "phone") {
  const what = channel === "email" ? "email address" : "phone number";
  return new Response(
    JSON.stringify({
      ok: true,
      message: `If this ${what} is registered, a 6-digit code will arrive shortly.`,
    }),
    {
      status: 200,
      headers: { ...CORS, "Content-Type": "application/json" },
    },
  );
}

function jsonError(status: number, error: string) {
  return new Response(JSON.stringify({ ok: false, error }), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS });
  }
  if (req.method !== "POST") {
    return jsonError(405, "Method not allowed");
  }

  let body: { email?: string; phone?: string };
  try {
    body = await req.json();
  } catch {
    return jsonError(400, "Invalid JSON body");
  }

  const email = body.email?.toString().toLowerCase().trim() || null;
  const phone = body.phone?.toString().trim() || null;

  // Exactly one of email/phone must be present.
  if ((!email && !phone) || (email && phone)) {
    return jsonError(400, "Provide exactly one of email or phone");
  }

  const channel: "email" | "phone" = email ? "email" : "phone";

  // Service-role client for the investor lookup (bypasses RLS, safe inside fn).
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  // Lookup by email or phone (active investors only).
  const lookup = email
    ? admin
        .from("investors")
        .select("id, email, phone")
        .ilike("email", email)
        .is("deleted_at", null)
        .limit(1)
        .maybeSingle()
    : admin
        .from("investors")
        .select("id, email, phone")
        .eq("phone", phone!)
        .is("deleted_at", null)
        .limit(1)
        .maybeSingle();

  const { data: investor, error: lookupErr } = await lookup;

  if (lookupErr) {
    console.error("[request-auth-email] investor lookup failed", lookupErr);
    // Still generic to the caller — don't leak DB errors.
    return genericReply(channel);
  }

  if (!investor) {
    console.log(
      `[request-auth-email] no investor found for ${channel}; returning generic reply`,
    );
    return genericReply(channel);
  }

  // Trigger Supabase Auth to send the OTP. We hit the REST endpoint with the
  // anon key (same path the client SDK uses) so Supabase honors its own rate
  // limits and email-template config.
  //
  // IMPORTANT: NO `redirect_to` / `email_redirect_to` is set here. Supabase
  // only treats this as a pure-OTP request (rendering `{{ .Token }}`) when
  // the redirect param is absent. Setting it forces a magic-link URL into
  // the email even if the template tries to render the token.
  const otpBody: Record<string, unknown> = { create_user: false };
  if (channel === "email") {
    otpBody.email = investor.email; // use canonical stored value
  } else {
    // Phone in Supabase auth is stored without leading '+'. The auth API
    // accepts both; keep it as the canonical investors.phone value.
    otpBody.phone = investor.phone;
  }

  try {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/otp`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        apikey: ANON_KEY,
      },
      body: JSON.stringify(otpBody),
    });
    if (!r.ok) {
      const text = await r.text();
      console.error(
        `[request-auth-email] /auth/v1/otp returned ${r.status}: ${text}`,
      );
      // Common cases:
      //   429 = rate limit — caller will get generic reply, user should wait
      //   422 = phone provider not configured (expected until SMS is set up)
    } else {
      console.log(
        `[request-auth-email] OTP dispatched via ${channel} for investor ${investor.id}`,
      );
    }
  } catch (e) {
    console.error("[request-auth-email] OTP fetch threw", e);
  }

  return genericReply(channel);
});
