/// Production support contact numbers used by Assistance / Support
/// CTAs (WhatsApp + tap-to-call). Single source of truth — import from
/// here so the same value drives every deep link.
///
/// Numbers are stored in E.164 format (`+<country><digits>`). The
/// WhatsApp deep link uses the digits-only form (`wa.me/<digits>`);
/// `tel:` links accept the full `+91…` form unchanged.
library;

/// Relationship Manager — investor account, payouts, and investment
/// questions.
const String kRmPhone = '+917022268125';

/// Tech support — app issues, login problems, bug reports.
const String kTechPhone = '+919699928661';
