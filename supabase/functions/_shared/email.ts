// Outbound email via Resend. Used for ARL ops notifications
// (new ticket, bank change request).
const RESEND_API = "https://api.resend.com/emails";

export interface EmailParams {
  to: string;
  subject: string;
  html: string;
  from?: string;
}

export async function sendEmail(params: EmailParams): Promise<void> {
  const apiKey = Deno.env.get("RESEND_API_KEY");
  if (!apiKey) {
    console.warn("RESEND_API_KEY not set — skipping email send");
    return;
  }
  const from = params.from ?? "ARL <noreply@agresearchlabs.com>";
  const res = await fetch(RESEND_API, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [params.to],
      subject: params.subject,
      html: params.html,
    }),
  });
  if (!res.ok) {
    const txt = await res.text();
    throw new Error(`Resend failed: ${res.status} ${txt}`);
  }
}
