/// PAN: keep first 5, last 1, mask the middle 4.
/// Example: RTYUI2468L → RTYUI****L
export function maskPan(pan: string | null | undefined): string | null {
  if (!pan) return null;
  const trimmed = pan.trim().toUpperCase();
  if (trimmed.length < 6) return trimmed; // too short to be a real PAN — store as-is
  const first = trimmed.slice(0, 5);
  const last = trimmed.slice(-1);
  return `${first}****${last}`;
}

/// Bank account: keep last 4, mask the rest in 4-char groups.
/// Example: 123456789012 → XXXX-XXXX-9012
export function maskBankAccount(acc: string | null | undefined): string | null {
  if (!acc) return null;
  const digits = acc.replace(/\D/g, "");
  if (digits.length < 4) return null;
  const last4 = digits.slice(-4);
  // Build the right number of XXXX groups based on length.
  const masked = digits.length >= 12
    ? `XXXX-XXXX-${last4}`
    : digits.length >= 8
    ? `XXXX-${last4}`
    : `XXXX-${last4}`;
  return masked;
}

/// Strip "%" and parse as number, returning null on failure.
export function parsePercent(v: unknown): number | null {
  if (v === null || v === undefined) return null;
  const s = String(v).replace(/%/g, "").trim();
  if (!s) return null;
  const n = Number(s);
  return Number.isFinite(n) ? n : null;
}
