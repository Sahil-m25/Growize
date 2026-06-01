import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/constants/support_contacts.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Login screen — OTP-only.
///
/// User enters an email and we POST it to the `request-auth-email`
/// Edge Function via [SessionManager.signInWithOtp]. The gate always
/// returns 200 (success vs "email unknown" is indistinguishable by
/// design — invite-only enumeration protection), so we always show
/// the same generic toast and push to `/otp` for the user to enter
/// the 6-digit code.
///
/// The phone-OTP path mentioned in the spec is intentionally NOT
/// wired here yet; this screen is structured around a single
/// "channel" field so adding the toggle later is a small change.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  bool _sending = false;
  String? _error;

  /// Lightweight email validator — same regex used elsewhere. We only
  /// use this to enable / disable the Send Code button so users get
  /// immediate feedback. Server-side gating happens server-side.
  static final _emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  @override
  void initState() {
    super.initState();
    _emailCtrl.addListener(() {
      // Cheap rebuild so the Send Code button enables / disables in
      // step with the field. Don't reset _error here — that would
      // hide the message the moment the user starts editing.
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  bool get _canSend =>
      !_sending && _emailRegex.hasMatch(_emailCtrl.text.trim().toLowerCase());

  Future<void> _sendCode() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (!_emailRegex.hasMatch(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });

    // Dev bypass — skip the network call entirely so design previews
    // work without backend config. Push straight to home so we don't
    // strand the user in the OTP screen with a fake email.
    if (SupabaseConstants.devBypassAuth || SupabaseConstants.isDemoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      context.go(RouteNames.home);
      return;
    }

    try {
      await SessionManager.signInWithOtp(email: email);
      if (!mounted) return;
      // Always show the same generic toast — the gate is designed so
      // we can't distinguish "sent" from "unknown email" and we don't
      // want the UI leaking that information either.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('If this email is registered, a code is on its way.'),
          duration: Duration(seconds: 4),
        ),
      );
      context.push(RouteNames.otp, extra: email);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'sign_in_otp_send'));
      if (!mounted) return;
      setState(() => _error = 'Could not send code: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openSupportWhatsApp() async {
    // wa.me uses the digits-only form of the E.164 number.
    final waUri = Uri.parse(
      'https://wa.me/${kTechPhone.replaceAll('+', '')}'
      '?text=${Uri.encodeComponent('Hi — I am having trouble logging in to Growize.')}',
    );
    final ok = await launchUrl(waUri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // UX call (preserved from the previous build): anchor the form
    // (logo → Send Code button) in the upper-mid of the viewport so
    // the primary CTA lands at roughly 55-60% of screen height. We
    // use ~18% of viewport for the top spacer rather than a fixed
    // 32px so the layout scales between small phones and tablets.
    final viewportH = MediaQuery.of(context).size.height;
    final topSpacer = (viewportH * 0.18).clamp(48.0, 220.0);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: topSpacer),
              Center(
                child: SizedBox(
                  width: 84,
                  height: 84,
                  child: Image.asset(
                    'assets/images/growize_g.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.high,
                    isAntiAlias: true,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Center(
                child: Text(
                  'Welcome to Growize',
                  style: TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              const Center(
                child: Text(
                  'Investment portal by AgResearch Labs',
                  style: TextStyle(color: ArlColors.muted, fontSize: 12),
                ),
              ),
              if (SupabaseConstants.devBypassAuth) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: ArlColors.gold.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'DEV BYPASS — auth disabled (ARL_DEV_BYPASS=true)',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: ArlColors.charcoal,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 36),
              // ── Email channel ──────────────────────────────────────
              // The screen is intentionally structured around a single
              // channel block so adding the phone-OTP toggle (when SMS
              // is enabled) becomes a swap of this widget, not a full
              // re-layout.
              _buildEmailChannel(),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: ArlColors.earth, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              // Trouble logging in? Contact support → WhatsApp tech line.
              Center(
                child: TextButton(
                  onPressed: _openSupportWhatsApp,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                  ),
                  child: const Text.rich(
                    TextSpan(
                      style: TextStyle(
                        color: ArlColors.muted,
                        fontSize: 12,
                      ),
                      children: [
                        TextSpan(text: 'Trouble logging in? '),
                        TextSpan(
                          text: 'Contact support',
                          style: TextStyle(
                            color: ArlColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  'By continuing, you agree to our Terms of Service',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: ArlColors.muted, fontSize: 10),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmailChannel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Email',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: ArlColors.sand),
          ),
          child: TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.send,
            autofillHints: const [AutofillHints.email, AutofillHints.username],
            onSubmitted: (_) {
              if (_canSend) _sendCode();
            },
            style: const TextStyle(fontSize: 14),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'you@example.com',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton(
          onPressed: _canSend ? _sendCode : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: ArlColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: ArlColors.primary.withOpacity(0.4),
            disabledForegroundColor: Colors.white.withOpacity(0.7),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            elevation: 0,
          ),
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2),
                )
              : const Text(
                  'Send Code',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
        ),
      ],
    );
  }
}
