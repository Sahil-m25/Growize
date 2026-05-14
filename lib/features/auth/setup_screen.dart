import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/legal/legal_content.dart';

final _panRegex = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
final _aadhaarRegex = RegExp(r'^[0-9]{12}$');
final _ifscRegex = RegExp(r'^[A-Z]{4}0[A-Z0-9]{6}$');
final _emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
final _dobRegex = RegExp(r'^([0-3]\d)-([0-1]\d)-([0-9]{4})$');

/// Initial onboarding for a new investor — 3-step wizard. Final submit
/// upserts the current user's `investors` row (RLS scoped to auth.uid()).
/// Raw PAN / Aadhaar / account numbers never reach the DB — only masked
/// projections are persisted.
class InitialSetupScreen extends ConsumerStatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  ConsumerState<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends ConsumerState<InitialSetupScreen> {
  int _step = 0;
  bool _submitting = false;
  // Tied to the consent checkbox on the bank step. Submit is blocked
  // until this is true. Persisted via UserSettingsRepository.recordLegalConsent
  // immediately after the investor row upsert.
  bool _consentChecked = false;

  final _formKeys = List.generate(3, (_) => GlobalKey<FormState>());

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _dob = TextEditingController();
  final _pan = TextEditingController();
  final _aadhaar = TextEditingController();
  final _bankName = TextEditingController();
  final _ifsc = TextEditingController();
  final _account = TextEditingController();
  final _holder = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pre-fill email from the signed-in auth user so it always matches
    // the JWT-bound identity on insert.
    final authEmail = ArlSupabase.client?.auth.currentUser?.email;
    if (authEmail != null) {
      _email.text = authEmail;
    }
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _email,
      _dob,
      _pan,
      _aadhaar,
      _bankName,
      _ifsc,
      _account,
      _holder
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _next() async {
    final form = _formKeys[_step].currentState;
    if (form != null && !form.validate()) return;

    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    if (!_consentChecked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Accept the Terms and Privacy Policy to continue'),
        ),
      );
      return;
    }
    await _submit();
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      await ref.read(investorRepositoryProvider).upsertOnboarding(
            name: _name.text.trim(),
            email: _email.text.trim(),
            dateOfBirth: _parseDob(_dob.text.trim()),
            panMasked: _maskPan(_pan.text.trim()),
            aadhaarMasked: _maskAadhaar(_aadhaar.text.trim()),
            bankName: _bankName.text.trim(),
            bankIfsc: _ifsc.text.trim(),
            bankAccountMasked: _maskAccount(_account.text.trim()),
            bankHolderName: _holder.text.trim().isEmpty
                ? _name.text.trim()
                : _holder.text.trim(),
          );
      // Record consent timestamps once the investor row is in place.
      // Errors here are non-fatal — the row is the source of truth for
      // onboarding completion, and the consent stamp can be back-filled
      // on next sign-in if it failed.
      try {
        await ref.read(userSettingsRepositoryProvider).recordLegalConsent();
      } catch (_) {}
      ref.invalidate(currentInvestorProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Onboarding submitted — KYC pending')),
      );
      router.go(RouteNames.home);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _back() {
    if (_submitting) return;
    if (_step > 0) {
      setState(() => _step--);
    } else {
      context.canPop() ? context.pop() : context.go(RouteNames.login);
    }
  }

  static DateTime? _parseDob(String input) {
    final m = _dobRegex.firstMatch(input);
    if (m == null) return null;
    final day = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final year = int.parse(m.group(3)!);
    try {
      return DateTime(year, month, day);
    } catch (_) {
      return null;
    }
  }

  static String _maskPan(String pan) {
    // ABCDE1234F -> ABCDE****F
    if (pan.length != 10) return pan;
    return '${pan.substring(0, 5)}****${pan.substring(9)}';
  }

  static String _maskAadhaar(String a) {
    // 12 digits -> XXXX-XXXX-1234
    if (a.length != 12) return a;
    return 'XXXX-XXXX-${a.substring(8)}';
  }

  static String _maskAccount(String acc) {
    if (acc.length <= 4) return acc;
    return 'X' * (acc.length - 4) + acc.substring(acc.length - 4);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back,
                        color: ArlColors.charcoal, size: 20),
                    onPressed: _submitting ? null : _back,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Get Started',
                    style: TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              child: _StepIndicator(step: _step, total: 3),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: KeyedSubtree(
                    key: ValueKey(_step),
                    child: _stepBody(),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ArlColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _step == 2 ? 'Submit for Verification' : 'Continue',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return Form(
          key: _formKeys[0],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: _PersonalStep(
            name: _name,
            email: _email,
            dob: _dob,
          ),
        );
      case 1:
        return Form(
          key: _formKeys[1],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: _IdStep(pan: _pan, aadhaar: _aadhaar),
        );
      default:
        return Form(
          key: _formKeys[2],
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: _BankStep(
            bank: _bankName,
            ifsc: _ifsc,
            account: _account,
            holder: _holder,
            consentChecked: _consentChecked,
            onConsentChanged: (v) =>
                setState(() => _consentChecked = v ?? false),
          ),
        );
    }
  }
}

class _StepIndicator extends StatelessWidget {
  final int step;
  final int total;
  const _StepIndicator({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final active = i <= step;
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: i < total - 1 ? 6 : 0),
            height: 4,
            decoration: BoxDecoration(
              color: active ? ArlColors.primary : ArlColors.sand,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}

class _PersonalStep extends StatelessWidget {
  final TextEditingController name, email, dob;
  const _PersonalStep(
      {required this.name, required this.email, required this.dob});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Personal Details',
          subtitle: 'Step 1 of 3 — Basic info',
        ),
        _Field(
          label: 'Full Name',
          hint: 'As per PAN',
          controller: name,
          validator: (v) => (v == null || v.trim().length < 2)
              ? 'Enter your full name'
              : null,
        ),
        _Field(
          label: 'Email',
          hint: 'name@example.com',
          controller: email,
          keyboard: TextInputType.emailAddress,
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return 'Enter your email';
            if (!_emailRegex.hasMatch(s)) return 'Invalid email format';
            return null;
          },
        ),
        _Field(
          label: 'Date of Birth',
          hint: 'DD-MM-YYYY',
          controller: dob,
          keyboard: TextInputType.datetime,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
            LengthLimitingTextInputFormatter(10),
          ],
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return 'Enter your date of birth';
            if (!_dobRegex.hasMatch(s)) return 'Use DD-MM-YYYY';
            final d = _InitialSetupScreenState._parseDob(s);
            if (d == null) return 'Invalid date';
            if (d.isAfter(DateTime.now())) return 'Date is in the future';
            return null;
          },
        ),
      ],
    );
  }
}

class _IdStep extends StatelessWidget {
  final TextEditingController pan, aadhaar;
  const _IdStep({required this.pan, required this.aadhaar});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Identity Verification',
          subtitle: 'Step 2 of 3 — KYC documents',
        ),
        _Field(
          label: 'PAN Number',
          hint: 'ABCDE1234F',
          controller: pan,
          inputFormatters: [
            UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(10),
          ],
          validator: (v) {
            final s = v?.trim().toUpperCase() ?? '';
            if (s.isEmpty) return 'Enter your PAN';
            if (!_panRegex.hasMatch(s)) {
              return 'Format: 5 letters, 4 digits, 1 letter';
            }
            return null;
          },
        ),
        _Field(
          label: 'Aadhaar Number',
          hint: '12 digits',
          controller: aadhaar,
          keyboard: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(12),
          ],
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return 'Enter your Aadhaar';
            if (!_aadhaarRegex.hasMatch(s)) return 'Aadhaar must be 12 digits';
            return null;
          },
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: ArlColors.gold.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.shield_outlined, color: ArlColors.gold, size: 16),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only the masked tail of these IDs is stored. Full numbers '
                  'are never sent to the server.',
                  style: TextStyle(color: ArlColors.charcoal, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BankStep extends StatelessWidget {
  final TextEditingController bank, ifsc, account, holder;
  final bool consentChecked;
  final ValueChanged<bool?> onConsentChanged;
  const _BankStep({
    required this.bank,
    required this.ifsc,
    required this.account,
    required this.holder,
    required this.consentChecked,
    required this.onConsentChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Bank Account',
          subtitle: 'Step 3 of 3 — For payouts',
        ),
        _Field(
          label: 'Bank Name',
          hint: 'e.g. HDFC Bank',
          controller: bank,
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Enter your bank' : null,
        ),
        _Field(
          label: 'IFSC Code',
          hint: 'HDFC0001234',
          controller: ifsc,
          inputFormatters: [
            UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(11),
          ],
          validator: (v) {
            final s = v?.trim().toUpperCase() ?? '';
            if (s.isEmpty) return 'Enter your IFSC code';
            if (!_ifscRegex.hasMatch(s)) {
              return 'Format: AAAA0XXXXXX (5th char is zero)';
            }
            return null;
          },
        ),
        _Field(
          label: 'Account Number',
          hint: 'Enter account',
          controller: account,
          keyboard: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) {
            final s = v?.trim() ?? '';
            if (s.isEmpty) return 'Enter your account number';
            if (s.length < 9 || s.length > 18) {
              return 'Account number must be 9–18 digits';
            }
            return null;
          },
        ),
        _Field(
          label: 'Account Holder Name',
          hint: 'Leave blank to use your name above',
          controller: holder,
        ),
        const SizedBox(height: 4),
        _ConsentBlock(
          checked: consentChecked,
          onChanged: onConsentChanged,
        ),
      ],
    );
  }
}

class _ConsentBlock extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool?> onChanged;
  const _ConsentBlock({required this.checked, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Checkbox(
            value: checked,
            onChanged: onChanged,
            activeColor: ArlColors.primary,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text.rich(
                TextSpan(
                  style: const TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 12,
                    height: 1.4,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    _LegalLink(
                      label: LegalDocs.termsTitle,
                      route: RouteNames.terms,
                    ),
                    const TextSpan(text: ' and '),
                    _LegalLink(
                      label: LegalDocs.privacyTitle,
                      route: RouteNames.privacy,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalLink extends WidgetSpan {
  _LegalLink({required String label, required String route})
      : super(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Builder(
            builder: (context) => GestureDetector(
              onTap: () => context.push(route),
              child: Text(
                label,
                style: const TextStyle(
                  color: ArlColors.primary,
                  fontSize: 12,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        );
}

class _StepHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  const _StepHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 11,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final TextInputType? keyboard;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboard,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 6),
          TextFormField(
            controller: controller,
            keyboardType: keyboard,
            inputFormatters: inputFormatters,
            validator: validator,
            style: const TextStyle(fontSize: 14, color: ArlColors.charcoal),
            decoration: InputDecoration(
              hintText: hint,
              filled: true,
              fillColor: Colors.white,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: ArlColors.sand),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: ArlColors.sand),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide:
                    const BorderSide(color: ArlColors.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide: const BorderSide(color: ArlColors.earth),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
                borderSide:
                    const BorderSide(color: ArlColors.earth, width: 1.5),
              ),
              errorStyle: const TextStyle(color: ArlColors.earth, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

class UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
