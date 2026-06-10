/// Canonical legal text for the ARL / Growize Investor Portal.
///
/// **Template notice:** the wording below is a conservative, lawyer-reviewable
/// baseline drafted for an Indian agri-investment portal. It has NOT been
/// reviewed by counsel. Before relying on either document in a dispute,
/// route the text through legal review and revise as needed. The
/// [effectiveDate] constants control which "Last updated" string both
/// screens render; bump them when the body changes.
library;

abstract final class LegalDocs {
  /// "Last updated" stamp shown at the top of both documents.
  static const String effectiveDate = '9 June 2026';
  static const String version = '1.1';

  /// Contact email rendered in both documents.
  static const String contactEmail = 'tech@agresearchlabs.com';

  /// Jurisdiction placeholder. Confirm with counsel before launch.
  static const String jurisdictionCity = 'Bangalore';
  static const String jurisdictionState = 'Karnataka';

  static const String entityName = 'Agri Research Labs Private Limited';
  static const String brandName = 'Growize';

  static const String templateBanner =
      'This document is a template. It has not yet been reviewed by '
      'independent legal counsel. Review with a qualified Indian lawyer '
      'before relying on it in a dispute.';

  // ── Privacy Policy ───────────────────────────────────────────────
  static const String privacyTitle = 'Privacy Policy';
  static const String privacyBody = '''
Last updated: $effectiveDate
Version: $version

$entityName (we, us, our) operates the $brandName Investor Portal
(the App). This Privacy Policy explains what personal data we collect,
why we collect it, how we use it, and the rights you have over it under
the Digital Personal Data Protection Act, 2023 (DPDP Act) and applicable
Indian law.

1. Who we are.
   We are $entityName, a company incorporated in India, operating
   the $brandName platform for retail and accredited investors in
   agricultural projects.

2. Data we collect.
   To establish and maintain your account, comply with Know Your Customer
   (KYC) and anti-money-laundering regulations, and process payouts, we
   collect:
   - Identity data — full name, date of birth, and the last 4 digits of
     PAN and Aadhaar (we deliberately do not store full PAN/Aadhaar
     numbers; only masked projections reach our servers).
   - Contact data — email address, phone number.
   - Bank data — bank name, IFSC, last 4 digits of the account number,
     and account holder name.
   - Investment data — units allocated, payouts, exit requests,
     consultation requests, and ticket history.
   - Technical data — device type, app version, IP address (only as part
     of standard request logs), and crash diagnostics.
   - Authentication data — hashed PIN (we never see your raw PIN),
     biometric-enabled flag (the actual biometric never leaves your
     device), session timestamps.

3. Why we collect it.
   - To comply with KYC, AML, and tax-reporting obligations under
     Indian law.
   - To execute and account for your investments and disburse returns.
   - To operate, secure, and improve the App.
   - To respond to support tickets, consultation requests, and exit
     requests you raise inside the App.
   - To send transactional notifications you have opted into.

4. Legal basis.
   We process your data on the bases of (a) compliance with a legal
   obligation (KYC, AML), (b) performance of a contract you entered into
   with us, and (c) your consent for purposes that are not strictly
   necessary (for example, optional marketing communications, when
   offered).

5. Where your data is stored.
   - Application data (database + documents) is hosted on Supabase in
     India (Mumbai region). Access is gated by row-level-security
     policies that scope each row to the authenticated user.
   - Customer relationship records are mirrored to Zoho CRM (Zoho
     Corporation), processed in India.

6. Third parties and cross-border transfer.
   We do not sell your personal data. We share it only with service
   providers acting on our instructions and strictly for the purposes
   above:
   - Supabase (database, storage, authentication) — India.
   - Zoho CRM (operations) — India.
   - Resend (transactional email and one-time passcodes) — United States.
   - Sentry (crash and error diagnostics; sensitive identifiers such as
     PAN and Aadhaar are scrubbed before transmission) — United States.
   - Netlify (web application hosting) — United States.
   - Any payment / payout processor disclosed to you at the time you opt
     in to a specific transaction.
   Some of these providers process limited personal data outside India,
   which the Digital Personal Data Protection Act permits except to
   territories the Government may restrict. We are actively working to
   migrate the United States-based services (Resend, Sentry, Netlify) to
   India-based alternatives.

7. Retention.
   We retain identity, contact, bank, and investment data for the
   duration of your relationship with us and for the period required by
   applicable Indian law thereafter (typically 8 years for
   financial-services records). Technical and crash diagnostics are
   retained for shorter operational windows.

8. Security.
   We apply commercially reasonable safeguards including TLS-encrypted
   transport, hashed PIN storage, masked sensitive fields, row-level
   security, and least-privilege backend access. No system is perfectly
   secure; you are responsible for keeping your sign-in credentials
   confidential.

9. Cookies and analytics.
   The App is not a web cookie product. We do not currently embed
   third-party analytics or advertising trackers. If this changes we
   will update this Policy and, where required, seek your renewed
   consent.

10. Your rights under the DPDP Act.
    You have the right to:
    - Access the personal data we hold about you.
    - Request correction of inaccurate or outdated data.
    - Request erasure of data we are not legally required to retain.
    - Withdraw any consent you previously granted for non-mandatory
      processing.
    - File a complaint with the Data Protection Board of India if you
      believe your rights have been infringed.

11. Grievance officer.
    For any data-protection grievance, please contact:
        $entityName — Grievance Officer
        Email: $contactEmail
        Address: $jurisdictionCity, $jurisdictionState, India
    We will acknowledge your grievance promptly and resolve it within 30
    days, in line with the Digital Personal Data Protection Rules, 2025.

12. Changes to this Policy.
    We may revise this Policy from time to time. Material revisions will
    be surfaced inside the App and may require you to re-accept the
    updated text before continuing to use the service.

13. Contact.
    For any questions about this Policy, email $contactEmail.
''';

  // ── Terms of Service ─────────────────────────────────────────────
  static const String termsTitle = 'Terms of Service';
  static const String termsBody = '''
Last updated: $effectiveDate
Version: $version

These Terms of Service (Terms) govern your access to and use of the
$brandName Investor Portal (the App) operated by $entityName
(we, us, our). By creating an account or continuing to use the App you
agree to be bound by these Terms.

1. Eligibility.
   You may use the App only if (a) you are an individual resident in
   India, (b) you are at least 18 years old and competent to enter into a
   binding contract under Indian law, and (c) you have successfully
   completed our Know Your Customer (KYC) verification. We may refuse,
   suspend, or terminate access at our sole discretion.

2. Account and credentials.
   You are responsible for the accuracy of the information you provide
   during onboarding and for keeping your sign-in credentials, PIN, and
   biometric authorisations confidential. You are responsible for
   activity that occurs under your account. Notify us at $contactEmail
   immediately if you suspect unauthorised access.

3. KYC requirement.
   Access to investment functionality is conditional on completion of
   KYC. We may at any time request additional documentation to comply
   with applicable Indian laws and regulations. We may suspend account
   activity while KYC is being reviewed or revalidated.

4. Nature of investments — risk disclosure.
   Investments offered through the App are in agricultural projects.
   Such investments are inherently risky. Returns are not guaranteed,
   may be partial, delayed, or zero, and your principal is at risk.
   Performance shown in the App is illustrative or historical and does
   not predict future outcomes. You are responsible for performing your
   own due diligence and consulting an independent financial adviser
   before committing capital. We do not provide investment, legal, or
   tax advice through this App.

5. Regulatory disclaimer.
   The App is not a stock exchange, mutual fund, or banking product.
   Where activity carried out through the App attracts a specific
   regulatory regime, we will comply with the applicable authority's
   requirements and disclose them to you. Nothing in these Terms
   overrides any rights you have as an investor under mandatory Indian
   law.

6. Investor responsibilities.
   You agree to (a) provide truthful information, (b) not use the App
   to launder funds or evade taxes, (c) keep your bank, address, and
   identity details up to date, and (d) comply with all applicable
   laws.

7. Prohibited use.
   You may not (a) attempt to gain unauthorised access to other users'
   accounts, (b) reverse-engineer or tamper with the App, (c) use the
   App in violation of any applicable law, (d) copy, redistribute, or
   commercialise our content without our prior written consent, or (e)
   use any automated agent to interact with the App without our prior
   written consent.

8. Intellectual property.
   The App, including its design, code, brand marks, project content,
   gallery imagery, and aggregated analytics, is owned by us or
   licensed to us. We grant you a limited, non-exclusive,
   non-transferable, revocable licence to use the App for the purpose
   of managing your own investments. No other rights are granted.

9. Termination.
   You may close your account at any time by contacting
   $contactEmail. We may suspend or terminate your access for breach
   of these Terms, for KYC or AML reasons, or where required by law.
   Termination does not extinguish accrued obligations on either side.

10. Limitation of liability.
    To the maximum extent permitted by applicable Indian law, our
    aggregate liability arising out of or in connection with your use
    of the App is limited to the management fees you have actually
    paid to us in the 12 months preceding the event giving rise to the
    claim. We are not liable for indirect, incidental, consequential,
    or punitive damages, lost profits, or lost data.

11. Indemnification.
    You agree to indemnify and hold us harmless against any claim
    arising from your breach of these Terms, your misuse of the App,
    or your violation of applicable law.

12. Dispute resolution and governing law.
    These Terms are governed by the laws of India. Any dispute arising
    out of or in connection with these Terms or your use of the App
    will be resolved through good-faith discussion in the first
    instance. Failing that, disputes are subject to the exclusive
    jurisdiction of the courts at $jurisdictionCity,
    $jurisdictionState, India (subject to legal review — see template
    notice above).

13. Severability.
    If any provision of these Terms is held to be unenforceable, the
    remaining provisions remain in full force.

14. Changes to these Terms.
    We may amend these Terms from time to time. Material amendments
    will be surfaced inside the App and may require you to re-accept
    the updated Terms before continuing to use the service.

15. Contact.
    For any question relating to these Terms, email $contactEmail.
''';
}
