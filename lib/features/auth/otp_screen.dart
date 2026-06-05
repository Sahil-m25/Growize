import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:arl_app/core/auth/web_session_native.dart'
    if (dart.library.js_interop) 'package:arl_app/core/auth/web_session_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/auth/auth_provider.dart';

/// OTP entry screen. Reached from LoginScreen via
/// `context.push('/otp', extra: email)`. Renders six single-digit
/// boxes with auto-advance / paste-to-fill, a resend button with a
/// 60s cooldown, and a "Change email" link that pops back to login.
class OtpScreen extends ConsumerStatefulWidget {
  final String email;
  const OtpScreen({super.key, required this.email});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _codeLength = 6;

  final List<TextEditingController> _otp =
      List.generate(_codeLength, (_) => TextEditingController());
  final List<FocusNode> _otpFocus =
      List.generate(_codeLength, (_) => FocusNode());

  bool _verifying = false;
  bool _resending = false;
  String? _error;
  int _secondsLeft = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    // Guard against direct navigation to /otp with no email (deep
    // link, page refresh on web). Without an email there's nothing
    // to verify against, so bounce the user to the login screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.email.trim().isEmpty) {
        context.go(RouteNames.login);
        return;
      }
      _otpFocus[0].requestFocus();
      // The code was just sent by the previous screen, so start the
      // resend cooldown immediately. This also prevents a quick
      // double submission from spamming the gate.
      _startCooldown(60);
    });
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    for (final c in _otp) {
      c.dispose();
    }
    for (final n in _otpFocus) {
      n.dispose();
    }
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _secondsLeft = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) t.cancel();
    });
  }

  String get _code => _otp.map((c) => c.text).join();

  /// Masks the local part of an email — keeps first + last char,
  /// replaces the middle with `****`. Single-character local parts
  /// fall back to the bare char with a `****` suffix so we still
  /// avoid echoing the full value.
  static String _maskEmail(String email) {
    final at = email.indexOf('@');
    if (at <= 0) return email;
    final local = email.substring(0, at);
    final domain = email.substring(at);
    if (local.length <= 2) return '${local[0]}****$domain';
    return '${local[0]}****${local[local.length - 1]}$domain';
  }

  Future<void> _verify(String code) async {
    if (code.length != _codeLength || _verifying) return;
    setState(() {
      _verifying = true;
      _error = null;
    });

    // Dev bypass — accept any 6-digit code in demo / dev builds.
    if (SupabaseConstants.devBypassAuth || SupabaseConstants.isDemoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      context.go(RouteNames.home);
      return;
    }

    try {
      await SessionManager.verifyEmailOtp(email: widget.email, token: code);
      if (!mounted) return;
      ref.invalidate(isLoggedInProvider);
      await _routeAfterLogin();
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      setState(() {
        _error = msg.contains('expired')
            ? 'Code expired, tap Resend'
            : 'Wrong code, try again';
      });
      // Clear the boxes + return focus to the first one so the user
      // can immediately retype without manually deleting.
      for (final c in _otp) {
        c.clear();
      }
      _otpFocus[0].requestFocus();
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'sign_in_otp_verify'));
      if (!mounted) return;
      setState(() => _error = 'Verification failed: $e');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _routeAfterLogin() async {
    // Check the server flag first. The on-device app-lock state
    // (AppLockService) is the source of truth for whether the lock
    // screen actually fires, but the server mirror tells us whether
    // THIS user has ever enabled biometric on any device — if so,
    // we skip the nudge and let the lock gate take over on next
    // launch. If they've never enabled it, surface the prompt.
    final client = ArlSupabase.client;
    if (client == null) {
      if (mounted) context.go(RouteNames.home);
      return;
    }
    Map<String, dynamic>? settings;
    try {
      settings = await client
          .from('user_settings')
          .select('biometric_enabled')
          .maybeSingle();
    } catch (_) {
      // Non-fatal — if the lookup fails we fall through to the nudge
      // (better to over-prompt than to silently skip enrollment).
      settings = null;
    }
    if (!mounted) return;
    // Seed the web idle timer on successful login.
    if (kIsWeb) refreshWebSession();
    // Web has no biometric support — skip setup screen entirely.
    if (kIsWeb || settings?['biometric_enabled'] == true) {
      context.go(RouteNames.home);
    } else {
      context.go(RouteNames.setupBiometric);
    }
  }

  Future<void> _resend() async {
    if (_secondsLeft > 0 || _resending) return;
    setState(() {
      _resending = true;
      _error = null;
    });
    try {
      if (SupabaseConstants.devBypassAuth || SupabaseConstants.isDemoMode) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      } else {
        await SessionManager.signInWithOtp(email: widget.email);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('If this email is registered, a code is on its way.'),
          duration: Duration(seconds: 3),
        ),
      );
      _startCooldown(60);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'sign_in_otp_resend'));
      if (!mounted) return;
      setState(() => _error = 'Could not resend: $e');
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  /// Paste-to-fill: if the user pastes a 6-digit string into any
  /// box, distribute the digits across the row and trigger verify.
  void _maybeHandlePaste(int index, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.length < _codeLength) return;
    final code = digits.substring(0, _codeLength);
    for (var i = 0; i < _codeLength; i++) {
      _otp[i].text = code[i];
    }
    _otpFocus[_codeLength - 1].unfocus();
    setState(() {});
    _verify(code);
  }

  @override
  Widget build(BuildContext context) {
    final viewportH = MediaQuery.of(context).size.height;
    final topSpacer = (viewportH * 0.10).clamp(32.0, 140.0);

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: ArlColors.charcoal),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(RouteNames.login);
            }
          },
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: topSpacer),
              Center(
                child: SizedBox(
                  width: 64,
                  height: 64,
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
                  'Check your inbox',
                  style: TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text.rich(
                    TextSpan(
                      style: const TextStyle(
                        color: ArlColors.muted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                      children: [
                        const TextSpan(
                            text: 'Enter the 6-digit code we sent to '),
                        TextSpan(
                          text: _maskEmail(widget.email),
                          style: const TextStyle(
                            color: ArlColors.charcoal,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              _buildOtpBoxes(),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: ArlColors.earth, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 22),
              _buildResendRow(),
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: _verifying
                      ? null
                      : () {
                          if (context.canPop()) {
                            context.pop();
                          } else {
                            context.go(RouteNames.login);
                          }
                        },
                  child: const Text(
                    'Change email',
                    style: TextStyle(
                      color: ArlColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_verifying)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: ArlColors.accent,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOtpBoxes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(_codeLength, (i) {
        final hasFocus = _otpFocus[i].hasFocus;
        return Padding(
          padding: EdgeInsets.only(right: i < _codeLength - 1 ? 10 : 0),
          child: SizedBox(
            width: 44,
            height: 56,
            child: Focus(
              onFocusChange: (_) => setState(() {}),
              child: TextField(
                controller: _otp[i],
                focusNode: _otpFocus[i],
                enabled: !_verifying,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: ArlColors.charcoal,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: ArlColors.cream,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: ArlColors.sand, width: 1.5),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: hasFocus ? ArlColors.primary : ArlColors.sand,
                      width: hasFocus ? 2 : 1.5,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: ArlColors.primary, width: 2),
                  ),
                ),
                onChanged: (value) {
                  // If the user pasted the full code into one box,
                  // distribute it across the row.
                  if (value.length > 1) {
                    _maybeHandlePaste(i, value);
                    // Keep only the first digit of the original box so
                    // the field doesn't show the full pasted blob.
                    _otp[i].value = TextEditingValue(
                      text: value.isNotEmpty ? value[0] : '',
                      selection: const TextSelection.collapsed(offset: 1),
                    );
                    return;
                  }
                  if (value.isNotEmpty && i < _codeLength - 1) {
                    _otpFocus[i + 1].requestFocus();
                  } else if (value.isEmpty && i > 0) {
                    _otpFocus[i - 1].requestFocus();
                  }
                  if (value.isNotEmpty && i == _codeLength - 1) {
                    final code = _code;
                    if (code.length == _codeLength) {
                      _otpFocus[i].unfocus();
                      _verify(code);
                    }
                  }
                  // Clear inline error as soon as the user edits.
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildResendRow() {
    final disabled = _secondsLeft > 0 || _resending || _verifying;
    final label = _resending
        ? 'Sending…'
        : _secondsLeft > 0
            ? 'Resend in ${_secondsLeft}s'
            : 'Resend code';
    return Center(
      child: TextButton(
        onPressed: disabled ? null : _resend,
        child: Text(
          label,
          style: TextStyle(
            color: disabled ? ArlColors.muted : ArlColors.primary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
