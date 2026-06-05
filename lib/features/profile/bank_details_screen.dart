import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/supabase/supabase_client.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/skel_box.dart';
import 'package:arl_app/core/providers/repositories.dart';

class BankDetailsScreen extends ConsumerWidget {
  const BankDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final investorAsync = ref.watch(currentInvestorProvider);
    final bankChangeReqs = ref.watch(
      FutureProvider<List<Map<String, dynamic>>>((ref) async {
        return ref.read(supportRepositoryProvider).myBankChangeRequests();
      }),
    );

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
              context.go(RouteNames.home);
            }
          },
        ),
        title: const Text(
          'Bank Details',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: investorAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SkelBox(height: 200),
          ),
        ),
        data: (investor) {
          if (investor == null) {
            return const Center(child: Text('No investor data'));
          }

          final bankName = investor['bank_name'] as String? ?? '';
          final accountMasked =
              investor['bank_account_masked'] as String? ?? '';
          final ifsc = investor['bank_ifsc'] as String? ?? '';
          final holderName = investor['bank_holder_name'] as String? ?? '';
          final kycStatus = investor['kyc_status'] as String? ?? '';
          final isVerified = kycStatus == 'verified';

          final hasPendingRequest = bankChangeReqs.maybeWhen(
            data: (reqs) => reqs.any((r) => r['status'] == 'pending'),
            orElse: () => false,
          );

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Single rounded-15 white card with sand dividers between
                  // fields � matches HTML pattern. Each field is a label
                  // + value row inside one card, NOT individually bordered.
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: Column(
                      children: [
                        _bankRow('Bank', bankName, isVerified: isVerified),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _bankRow('Account Number', accountMasked),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _bankRow('IFSC', ifsc),
                        const Divider(
                            height: 1, color: ArlColors.sand, thickness: 1),
                        _bankRow('Account Holder', holderName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (isVerified)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.green.withOpacity(0.3),
                        ),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.verified,
                            color: Colors.green,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Verified',
                            style: TextStyle(
                              color: Colors.green,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (hasPendingRequest) ...[
                    const SizedBox(height: 20),
                    // Pending request banner � sand tint per HTML
                    // pattern (NOT generic warning orange).
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ArlColors.sand.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ArlColors.sand),
                      ),
                      child: const Row(
                        children: [
                          Icon(
                            Icons.schedule,
                            color: ArlColors.charcoal,
                            size: 20,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Change pending review',
                            style: TextStyle(
                              color: ArlColors.charcoal,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  // Gradient-primary CTA � primary?accent rounded-15 card
                  // wrapping InkWell. Matches HTML "gradient-primary"
                  // button styling used across the app.
                  Material(
                    color: Colors.transparent,
                    child: Ink(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [ArlColors.primary, ArlColors.accent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(15),
                        onTap: () => _showRequestChangeModal(context, ref),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.edit_outlined,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 10),
                              Text(
                                'Update Bank Account',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showRequestChangeModal(BuildContext context, WidgetRef ref) {
    final bankNameController = TextEditingController();
    final accountController = TextEditingController();
    final ifscController = TextEditingController();
    final holderController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ArlColors.cream,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Request Bank Change',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ArlColors.charcoal,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: bankNameController,
                decoration: InputDecoration(
                  labelText: 'Bank Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: accountController,
                decoration: InputDecoration(
                  labelText: 'Account Number',
                  hintText: 'Enter your account number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ifscController,
                decoration: InputDecoration(
                  labelText: 'IFSC Code',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: holderController,
                decoration: InputDecoration(
                  labelText: 'Account Holder Name',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          setState(() => isSubmitting = true);
                          await _submitBankChange(
                            sheetContext,
                            ref,
                            bankNameController.text,
                            accountController.text,
                            ifscController.text,
                            holderController.text,
                          );
                          if (sheetContext.mounted) {
                            setState(() => isSubmitting = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ArlColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text('Submit'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitBankChange(
    BuildContext sheetContext,
    WidgetRef ref,
    String bankName,
    String accountRaw,
    String ifsc,
    String holderName,
  ) async {
    if (bankName.isEmpty ||
        accountRaw.isEmpty ||
        ifsc.isEmpty ||
        holderName.isEmpty) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(content: Text('All fields are required')),
      );
      return;
    }

    final accountMasked = _maskAccountNumber(accountRaw);
    if (accountMasked.isEmpty) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(content: Text('Invalid account number')),
      );
      return;
    }

    try {
      await ref.read(supportRepositoryProvider).requestBankChange(
            bankName: bankName,
            accountMasked: accountMasked,
            ifsc: ifsc,
            holderName: holderName,
          );

      // Fire-and-forget email notification to ops — non-fatal if it fails.
      final investor = await ref.read(currentInvestorProvider.future);
      ArlSupabase.client?.functions.invoke(
        'notify-bank-update',
        body: {
          'investorName': investor?['name'] ?? '',
          'investorEmail': investor?['email'] ?? '',
          'bankName': bankName,
          'bankIfsc': ifsc,
          'bankAccountMasked': accountMasked,
          'bankHolderName': holderName,
        },
      );

      if (!sheetContext.mounted) return;
      Navigator.pop(sheetContext);
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        const SnackBar(
          content: Text(
            'Request submitted. Our team will contact you within 2 business days.',
          ),
        ),
      );
      ref.invalidate(currentInvestorProvider);
    } catch (e) {
      String errorMsg = 'Could not submit request. Try again.';
      if (e.toString().contains('429')) {
        errorMsg = 'You already have a pending request';
      } else if (e.toString().contains('400')) {
        errorMsg = 'Invalid account number';
      }
      if (!sheetContext.mounted) return;
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
    }
  }

  String _maskAccountNumber(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty || digits.length < 4) return '';
    if (digits.length >= 4) {
      final last4 = digits.substring(digits.length - 4);
      return 'XXXX-XXXX-$last4';
    }
    return '';
  }

  Widget _bankRow(String label, String value, {bool isVerified = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: ArlColors.muted,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isVerified)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'KYC',
                style: TextStyle(
                  color: Colors.green,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
