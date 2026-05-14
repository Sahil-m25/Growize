import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:arl_app/core/auth/biometric_guard.dart';
import 'package:arl_app/core/auth/secure_session_store.dart';
import 'package:arl_app/core/auth/session_manager.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/auth/auth_provider.dart';

/// Login screen — supports email + password (primary) and email OTP (fallback).
/// Phone OTP isn't wired to a provider yet; we keep it commented for later.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _Mode { password, otpRequest, otpVerify }

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final List<TextEditingController> _otp =
      List.generate(6, (_) => TextEditingController());
  final List<FocusNode> _otpFocus = List.generate(6, (_) => FocusNode());

  _Mode _mode = _Mode.password;
  bool _busy = false;
  bool _passwordHidden = true;
  String? _error;
  bool _biometricAvailable = false;
  final _secureStore = SecureSessionStore();

  @override
  void initState() {
    super.initState();
    _bootstrapBiometric();
  }

  Future<void> _bootstrapBiometric() async {
    if (SupabaseConstants.devBypassAuth || SupabaseConstants.isDemoMode) {
      return;
    }
    try {
      final enabled = await _secureStore.readBiometricEnabled();
      if (!enabled) return;
      final email = await _secureStore.readEmail();
      final token = await _secureStore.readRefreshToken();
      if (email == null || token == null) return;
      final canUse = await BiometricGuard.isAvailable();
      if (!canUse || !mounted) return;
      setState(() {
        _biometricAvailable = true;
        if (_emailCtrl.text.isEmpty) _emailCtrl.text = email;
      });
    } catch (_) {
      // Cache-only — never block password sign-in on a probe failure.
    }
  }

  Future<void> _signInBiometric() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final passed = await BiometricGuard.authenticate();
      if (!passed) {
        setState(() => _busy = false);
        return;
      }
      final token = await _secureStore.readRefreshToken();
      if (token == null) {
        setState(() {
          _busy = false;
          _biometricAvailable = false;
          _error = 'Biometric session expired — sign in with password.';
        });
        await _secureStore.clearBiometric();
        return;
      }
      await SessionManager.signInWithRefreshToken(token);
      if (!mounted) return;
      ref.invalidate(isLoggedInProvider);
      context.go(RouteNames.home);
    } on AuthException catch (e) {
      // Refresh token rejected (revoked / expired). Wipe local cache so
      // the button stops appearing until password re-auth refreshes it.
      await _secureStore.clearBiometric();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _biometricAvailable = false;
        _error = e.message;
      });
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'sign_in_biometric'));
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Biometric sign-in failed: $e';
        });
      }
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    for (final c in _otp) {
      c.dispose();
    }
    for (final n in _otpFocus) {
      n.dispose();
    }
    super.dispose();
  }

  bool _isValidEmail(String s) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

  Future<void> _signInPassword() async {
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Enter your password');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    // Dev bypass — skip the network call.
    if (SupabaseConstants.devBypassAuth || SupabaseConstants.isDemoMode) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;
      context.go(RouteNames.home);
      return;
    }

    try {
      await SessionManager.signInWithEmailPassword(
        email: email,
        password: password,
      );
      if (!mounted) return;
      // Force isLoggedInProvider to re-evaluate immediately; otherwise
      // the cached value lags the auth-state stream and the GoRouter
      // redirect can bounce to /auth on the first tap.
      ref.invalidate(isLoggedInProvider);
      context.go(RouteNames.home);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'sign_in_password'));
      setState(() => _error = 'Sign-in failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEmailOtp() async {
    final email = _emailCtrl.text.trim();
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionManager.signInWithOtp(email: email);
      if (!mounted) return;
      setState(() => _mode = _Mode.otpVerify);
      _otpFocus[0].requestFocus();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'sign_in_otp_send'));
      setState(() => _error = 'Could not send code: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _verifyEmailOtp() async {
    final code = _otp.map((c) => c.text).join();
    if (code.length < 6) {
      setState(() => _error = 'Enter the 6-digit code');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await SessionManager.verifyEmailOtp(
        email: _emailCtrl.text.trim(),
        token: code,
      );
      if (!mounted) return;
      ref.invalidate(isLoggedInProvider);
      context.go(RouteNames.home);
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e, stack) {
      await Sentry.captureException(e,
          stackTrace: stack,
          withScope: (s) => s.setTag('flow', 'sign_in_otp_verify'));
      setState(() => _error = 'Verification failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// B.T4: Show forgot password modal.
  Future<void> _showForgotPasswordModal() async {
    final emailCtrl = TextEditingController();
    bool busy = false;

    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) => AlertDialog(
          backgroundColor: ArlColors.cream,
          title: const Text(
            'Reset password',
            style: TextStyle(
              color: ArlColors.charcoal,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Enter your email to receive a password reset link.',
                style: TextStyle(color: ArlColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: emailCtrl,
                enabled: !busy,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'you@example.com',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: ArlColors.sand),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: ArlColors.sand),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: busy
                  ? null
                  : () async {
                      final email = emailCtrl.text.trim();
                      if (email.isEmpty) return;

                      setDialogState(() => busy = true);
                      try {
                        await SessionManager.requestPasswordReset(email);
                        if (dialogCtx.mounted) {
                          Navigator.pop(dialogCtx);
                        }
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Password reset link sent to your email',
                              ),
                              duration: Duration(seconds: 3),
                            ),
                          );
                        }
                      } on AuthException catch (e) {
                        setDialogState(() {});
                        if (dialogCtx.mounted) {
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text(e.message)),
                          );
                        }
                      } catch (e) {
                        setDialogState(() {});
                        if (dialogCtx.mounted) {
                          ScaffoldMessenger.of(dialogCtx).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                      }
                    },
              child: busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send reset link'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 32),
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [ArlColors.primary, ArlColors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: ArlColors.primary.withValues(alpha: 0.25),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Text(
                      'ARL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
                    color: ArlColors.gold.withValues(alpha: 0.18),
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
              if (_mode == _Mode.password) _buildPasswordStage(),
              if (_mode == _Mode.otpRequest) _buildOtpRequestStage(),
              if (_mode == _Mode.otpVerify) _buildOtpVerifyStage(),
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 32),
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

  // ── Email + password ─────────────────────────────────────────────────
  Widget _buildPasswordStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_biometricAvailable) ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _signInBiometric,
            icon: const Icon(Icons.fingerprint, color: ArlColors.primary),
            label: const Text(
              'Use biometric',
              style: TextStyle(
                color: ArlColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: const BorderSide(color: ArlColors.primary, width: 1.2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(child: Divider(color: ArlColors.sand)),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'or',
                  style: TextStyle(color: ArlColors.muted, fontSize: 11),
                ),
              ),
              Expanded(child: Divider(color: ArlColors.sand)),
            ],
          ),
          const SizedBox(height: 18),
        ],
        _label('Email'),
        const SizedBox(height: 8),
        _textField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          hint: 'you@example.com',
          autofillHints: const [AutofillHints.email, AutofillHints.username],
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        _label('Password'),
        const SizedBox(height: 8),
        _textField(
          controller: _passwordCtrl,
          obscure: _passwordHidden,
          hint: '••••••••',
          autofillHints: const [AutofillHints.password],
          textInputAction: TextInputAction.done,
          onSubmitted: (_) {
            if (!_busy) _signInPassword();
          },
          suffix: IconButton(
            icon: Icon(_passwordHidden
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined),
            color: ArlColors.muted,
            onPressed: () => setState(() => _passwordHidden = !_passwordHidden),
          ),
        ),
        const SizedBox(height: 20),
        _primaryButton(
          label: 'Sign in',
          onTap: _signInPassword,
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _error = null;
                        _mode = _Mode.otpRequest;
                      }),
              child: const Text(
                'Use a one-time code',
                style: TextStyle(color: ArlColors.muted, fontSize: 12),
              ),
            ),
            const Text(
              '•',
              style: TextStyle(color: ArlColors.muted, fontSize: 12),
            ),
            TextButton(
              onPressed: _busy ? null : _showForgotPasswordModal,
              child: const Text(
                'Forgot password?',
                style: TextStyle(color: ArlColors.muted, fontSize: 12),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── OTP request ──────────────────────────────────────────────────────
  Widget _buildOtpRequestStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('Email'),
        const SizedBox(height: 8),
        _textField(
          controller: _emailCtrl,
          keyboardType: TextInputType.emailAddress,
          hint: 'you@example.com',
          autofillHints: const [AutofillHints.email, AutofillHints.username],
        ),
        const SizedBox(height: 20),
        _primaryButton(label: 'Send code', onTap: _sendEmailOtp),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _error = null;
                      _mode = _Mode.password;
                    }),
            child: const Text(
              'Back to password sign-in',
              style: TextStyle(color: ArlColors.muted, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ── OTP verify ───────────────────────────────────────────────────────
  Widget _buildOtpVerifyStage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Sent to ${_emailCtrl.text.trim()}',
          style: const TextStyle(color: ArlColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (i) {
            return SizedBox(
              width: 44,
              height: 52,
              child: TextField(
                controller: _otp[i],
                focusNode: _otpFocus[i],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                maxLength: 1,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: ArlColors.charcoal,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: EdgeInsets.zero,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: ArlColors.sand),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: ArlColors.sand),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: ArlColors.primary, width: 1.5),
                  ),
                ),
                onChanged: (v) {
                  if (v.isNotEmpty && i < 5) {
                    _otpFocus[i + 1].requestFocus();
                  } else if (v.isEmpty && i > 0) {
                    _otpFocus[i - 1].requestFocus();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 20),
        _primaryButton(label: 'Verify & continue', onTap: _verifyEmailOtp),
        const SizedBox(height: 12),
        Center(
          child: TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _error = null;
                      _mode = _Mode.otpRequest;
                      for (final c in _otp) {
                        c.clear();
                      }
                    }),
            child: const Text(
              'Use a different email',
              style: TextStyle(color: ArlColors.muted, fontSize: 12),
            ),
          ),
        ),
      ],
    );
  }

  // ── Shared primitives ────────────────────────────────────────────────
  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          color: ArlColors.charcoal,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    Iterable<String>? autofillHints,
    Widget? suffix,
    TextInputAction? textInputAction,
    ValueChanged<String>? onSubmitted,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        autofillHints: autofillHints,
        textInputAction: textInputAction,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hint,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          suffixIcon: suffix,
        ),
        style: const TextStyle(fontSize: 14),
      ),
    );
  }

  Widget _primaryButton(
      {required String label, required Future<void> Function() onTap}) {
    return ElevatedButton(
      onPressed: _busy ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: ArlColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        elevation: 0,
      ),
      child: _busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: Colors.white, strokeWidth: 2),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
    );
  }
}
