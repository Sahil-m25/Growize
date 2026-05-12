import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Initial onboarding for new investor — 3-step wizard.
class InitialSetupScreen extends StatefulWidget {
  const InitialSetupScreen({super.key});

  @override
  State<InitialSetupScreen> createState() => _InitialSetupScreenState();
}

class _InitialSetupScreenState extends State<InitialSetupScreen> {
  int _step = 0;

  final _name = TextEditingController();
  final _email = TextEditingController();
  final _dob = TextEditingController();
  final _pan = TextEditingController();
  final _aadhaar = TextEditingController();
  final _bankName = TextEditingController();
  final _ifsc = TextEditingController();
  final _account = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _dob.dispose();
    _pan.dispose();
    _aadhaar.dispose();
    _bankName.dispose();
    _ifsc.dispose();
    _account.dispose();
    super.dispose();
  }

  void _next() {
    if (_step < 2) {
      setState(() => _step++);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Setup submitted — verification pending')),
      );
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) context.go(RouteNames.home);
      });
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      context.canPop() ? context.pop() : context.go(RouteNames.login);
    }
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
                    onPressed: _back,
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
                  onPressed: _next,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ArlColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
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
        return _PersonalStep(name: _name, email: _email, dob: _dob);
      case 1:
        return _IdStep(pan: _pan, aadhaar: _aadhaar);
      default:
        return _BankStep(bank: _bankName, ifsc: _ifsc, account: _account);
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
        _Field(label: 'Full Name', hint: 'As per PAN', controller: name),
        _Field(
            label: 'Email',
            hint: 'name@example.com',
            controller: email,
            keyboard: TextInputType.emailAddress),
        _Field(
            label: 'Date of Birth',
            hint: 'DD-MM-YYYY',
            controller: dob,
            keyboard: TextInputType.datetime),
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
                  'Documents are encrypted and used only for KYC verification.',
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
  final TextEditingController bank, ifsc, account;
  const _BankStep(
      {required this.bank, required this.ifsc, required this.account});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _StepHeader(
          title: 'Bank Account',
          subtitle: 'Step 3 of 3 — For payouts',
        ),
        _Field(label: 'Bank Name', hint: 'e.g. HDFC Bank', controller: bank),
        _Field(
          label: 'IFSC Code',
          hint: 'HDFC0001234',
          controller: ifsc,
          inputFormatters: [
            UpperCaseFormatter(),
            LengthLimitingTextInputFormatter(11),
          ],
        ),
        _Field(
          label: 'Account Number',
          hint: 'Enter account',
          controller: account,
          keyboard: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
      ],
    );
  }
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
  const _Field({
    required this.label,
    required this.hint,
    required this.controller,
    this.keyboard,
    this.inputFormatters,
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
          TextField(
            controller: controller,
            keyboardType: keyboard,
            inputFormatters: inputFormatters,
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
                borderSide: const BorderSide(color: ArlColors.primary, width: 1.5),
              ),
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
