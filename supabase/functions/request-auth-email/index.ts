// @ts-nocheck — source recovered from the deployed v10 bundle (types were
// stripped by the bundler); behaviour-identical except the v11 lookup gate.
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
// Version 11 (2026-09-26): App Access gate. Investors whose
// investors.app_access = 'hold' (created from Zoho but not yet invited) get
// the same generic reply as unknown addresses and NO code is sent. Their
// auth user is also suspended by zoho-crm-webhook v36, so the raw auth API
// cannot sign them in either.
//
// Version 7 (2026-08-24): CORS fix. v6 dropped x-arl-cron-secret from
// Access-Control-Allow-Headers, which broke every already-built client:
// those bundles still SEND that header, so the browser preflight failed
// and login died with "Failed to fetch" before a request was ever made.
// The header is allowed again purely for backward compatibility -- its
// value is still never read. Once every client is rebuilt without it this
// entry can go.
//
// Version 6 (2026-08-24): Rate limited. This function runs with
// verify_jwt:false and previously had no throttle at all, so anyone could
// POST a known investor's address on a loop and bomb them with OTP mail.
//
// The throttle runs BEFORE the investor lookup, deliberately: throttling
// after the lookup would make a 429 a reliable "this address is
// registered" oracle, undoing the generic-reply design below.
//
// Version 5 (2026-05-25): The Magic Link email template must render
// `{{ .Token }}` (the 6-digit code), NOT `{{ .ConfirmationURL }}` -- that's a
// Dashboard-only setting under Authentication -> Email Templates -> Magic
// Link. This function deliberately omits `emailRedirectTo` / `redirect_to`
// so Supabase issues a pure-token OTP rather than a magic-link URL.
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL");
const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY");
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const CORS = {
  "Access-Control-Allow-Origin": "*",
  // x-arl-cron-secret is listed for BACKWARD COMPATIBILITY ONLY. Shipped
  // clients still send it; omitting it here fails their preflight and the
  // login screen shows "Failed to fetch". The value is never read.
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-arl-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS"
};
// Sliding-window budgets, enforced in Postgres (public.check_auth_throttle).
// Edge functions are spun up per-instance, so an in-memory counter would
// reset constantly and throttle nothing in practice.
const ADDR_LIMIT = 3; // sends per address per window
const IP_LIMIT = 10; // sends per source IP per window (NAT'd offices)
const WINDOW_SECS = 900; // 15 minutes
function clientIp(req) {
  const fwd = req.headers.get("x-forwarded-for") ?? "";
  return fwd.split(",")[0].trim() || "unknown";
}
function tooManyRequests() {
  return new Response(JSON.stringify({
    ok: false,
    error: "Too many requests. Please wait a few minutes and try again."
  }), {
    status: 429,
    headers: {
      ...CORS,
      "Content-Type": "application/json",
      "Retry-After": "900"
    }
  });
}
function genericReply(channel) {
  const what = channel === "email" ? "email address" : "phone number";
  return new Response(JSON.stringify({
    ok: true,
    message: `If this ${what} is registered, a 6-digit code will arrive shortly.`
  }), {
    status: 200,
    headers: {
      ...CORS,
      "Content-Type": "application/json"
    }
  });
}
function jsonError(status, error) {
  return new Response(JSON.stringify({
    ok: false,
    error
  }), {
    status,
    headers: {
      ...CORS,
      "Content-Type": "application/json"
    }
  });
}
Deno.serve(async (req)=>{
  if (req.method === "OPTIONS") {
    return new Response(null, {
      headers: CORS
    });
  }
  if (req.method !== "POST") {
    return jsonError(405, "Method not allowed");
  }
  let body;
  try {
    body = await req.json();
  } catch  {
    return jsonError(400, "Invalid JSON body");
  }
  const email = body.email?.toString().toLowerCase().trim() || null;
  const phone = body.phone?.toString().trim() || null;
  // Exactly one of email/phone must be present.
  if (!email && !phone || email && phone) {
    return jsonError(400, "Provide exactly one of email or phone");
  }
  const channel = email ? "email" : "phone";
  // Service-role client for the investor lookup (bypasses RLS, safe inside fn).
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY, {
    auth: {
      persistSession: false,
      autoRefreshToken: false
    }
  });
  // --- Rate limit, BEFORE any lookup ---------------------------------
  // Keyed on what the caller submitted, not on anything we looked up, so
  // the 429 carries no information about whether the address exists.
  // Fail-open on an infrastructure error: a throttle outage must not lock
  // every investor out of signing in.
  const target = (email ?? phone).toLowerCase();
  const ip = clientIp(req);
  try {
    const [addrCheck, ipCheck] = await Promise.all([
      admin.rpc("check_auth_throttle", {
        p_key: `addr:${target}`,
        p_limit: ADDR_LIMIT,
        p_window_secs: WINDOW_SECS
      }),
      admin.rpc("check_auth_throttle", {
        p_key: `ip:${ip}`,
        p_limit: IP_LIMIT,
        p_window_secs: WINDOW_SECS
      })
    ]);
    if (addrCheck.error || ipCheck.error) {
      console.error("[request-auth-email] throttle check errored, failing open", addrCheck.error ?? ipCheck.error);
    } else if (addrCheck.data === false || ipCheck.data === false) {
      console.warn(`[request-auth-email] throttled ${addrCheck.data === false ? "address" : "ip"} (ip=${ip})`);
      return tooManyRequests();
    }
  } catch (e) {
    console.error("[request-auth-email] throttle threw, failing open", e);
  }
  // Lookup by email or phone (active investors only).
  const lookup = email ? admin.from("investors").select("id, email, phone, app_access").ilike("email", email).is("deleted_at", null).limit(1).maybeSingle() : admin.from("investors").select("id, email, phone, app_access").eq("phone", phone).is("deleted_at", null).limit(1).maybeSingle();
  const { data: investor, error: lookupErr } = await lookup;
  if (lookupErr) {
    console.error("[request-auth-email] investor lookup failed", lookupErr);
    // Still generic to the caller -- don't leak DB errors.
    return genericReply(channel);
  }
  if (!investor) {
    console.log(`[request-auth-email] no investor found for ${channel}; returning generic reply`);
    return genericReply(channel);
  }
  // v11: not invited yet -> behave exactly like an unknown address.
  if (investor.app_access === "hold") {
    console.log(`[request-auth-email] investor ${investor.id} is on hold; no code sent`);
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
  const otpBody = {
    create_user: false
  };
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
        apikey: ANON_KEY
      },
      body: JSON.stringify(otpBody)
    });
    if (!r.ok) {
      const text = await r.text();
      console.error(`[request-auth-email] /auth/v1/otp returned ${r.status}: ${text}`);
    // Common cases:
    //   429 = rate limit -- caller will get generic reply, user should wait
    //   422 = phone provider not configured (expected until SMS is set up)
    } else {
      console.log(`[request-auth-email] OTP dispatched via ${channel} for investor ${investor.id}`);
    }
  } catch (e) {
    console.error("[request-auth-email] OTP fetch threw", e);
  }
  return genericReply(channel);
});
