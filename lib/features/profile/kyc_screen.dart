import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/providers/repositories.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/core/widgets/skel_box.dart';

class KycScreen extends ConsumerWidget {
  const KycScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final investorAsync = ref.watch(currentInvestorProvider);

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
          'KYC Details',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
      ),
      body: investorAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: ArlColors.primary),
        ),
        error: (_, __) => const Center(
          child: Padding(
            padding: EdgeInsets.all(16),
            child: SkelBox(height: 200),
          ),
        ),
        data: (investor) {
          if (investor == null) {
            return const Center(child: Text('Not signed in'));
          }
          final name = (investor['name'] as String?) ?? '';
          final pan = (investor['pan_masked'] as String?) ?? '—';
          final aadhaar = (investor['aadhaar_masked'] as String?) ?? '—';
          final dobRaw = investor['date_of_birth'] as String?;
          final dob = dobRaw != null && dobRaw.isNotEmpty
              ? DateFormat('dd MMM yyyy').format(DateTime.parse(dobRaw))
              : '—';
          final address = _composeAddress(investor);
          final kycStatus =
              ((investor['kyc_status'] as String?) ?? 'pending').toLowerCase();
          final isVerified = kycStatus == 'verified';
          final isRejected = kycStatus == 'rejected';
          // Use created_at for the "Submitted on" date — updated_at changes
          // on every row touch (background syncs, etc.) and would show today.
          final createdRaw = investor['created_at'] as String?;
          final submittedOn = createdRaw != null && createdRaw.isNotEmpty
              ? DateFormat('dd MMM yyyy')
                  .format(DateTime.parse(createdRaw).toLocal())
              : null;

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _topStatusBanner(kycStatus, submittedOn),
                  const SizedBox(height: 12),
                  _ConfidentialityBanner(),
                  const SizedBox(height: 16),
                  _kycField('Full Name', name.isEmpty ? '—' : name,
                      isVerified: isVerified),
                  _kycField('PAN Number', pan),
                  _kycField('Aadhaar', aadhaar),
                  _kycField('Date of Birth', dob),
                  _kycField('Address', address),
                  if (isRejected) ...[
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                  'Contact support to re-submit your KYC documents.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: const Text(
                          'Re-submit KYC',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ArlColors.earth,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Top status banner shown after the AppBar — single white card with a
  /// circular shield icon (status-tinted), title (e.g. "KYC Verified") and
  /// "Submitted on $date" sub-text. Replaces the previous bottom-of-screen
  /// chip banner.
  Widget _topStatusBanner(String kycStatus, String? submittedOn) {
    final (Color color, String title, IconData icon) = switch (kycStatus) {
      'verified' => (ArlColors.accent, 'KYC Verified', Icons.verified_user),
      'in_progress' => (ArlColors.gold, 'KYC In Progress', Icons.hourglass_top),
      'rejected' => (ArlColors.earth, 'KYC Rejected', Icons.error_outline),
      _ => (ArlColors.muted, 'KYC Pending', Icons.shield_outlined),
    };
    final subtitle = submittedOn == null
        ? 'Your verification status will update once reviewed.'
        : (kycStatus == 'verified'
            ? 'Verified on $submittedOn'
            : 'Submitted on $submittedOn');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: ArlColors.muted,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _composeAddress(Map<String, dynamic> i) {
    final parts = [
      i['address_line1'],
      i['city'],
      i['state'],
      i['pincode'],
      i['country'],
    ]
        .map((v) => (v ?? '').toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  Widget _ConfidentialityBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF3C5152).withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFF3C5152).withOpacity(0.15),
        ),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 14, color: Color(0xFF3C5152)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This information is confidential and for your use only. '
              'ARL does not share your personal data with any third parties.',
              style: TextStyle(
                color: Color(0xFF3C5152),
                fontSize: 11,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kycField(String label, String value, {bool isVerified = false}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ArlColors.sand, width: 1),
      ),
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
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          if (isVerified)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Verified',
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
