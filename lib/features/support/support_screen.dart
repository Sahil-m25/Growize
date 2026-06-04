import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:arl_app/core/constants/support_contacts.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/onboarding/tour_keys.dart';

/// WhatsApp green — matches the v2 HTML mockup spec (`#25D366`).
const _whatsappGreen = Color(0xFF25D366);

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: Colors.white,
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
          'Assistance',
          style: TextStyle(
            color: ArlColors.charcoal,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GET HELP FAST',
              style: TextStyle(
                color: ArlColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
            ),
            const SizedBox(height: 8),
            _WhatsAppCta(
              key: TourKeys.supportWhatsappTech,
              title: 'WhatsApp Tech Support',
              subtitle: 'Quick reply for app issues',
              onTap: () => _openWhatsApp(
                context,
                phone: kTechPhone,
                preset: 'Hi, this is a tech / app issue: ',
              ),
            ),
            const SizedBox(height: 8),
            _WhatsAppCta(
              title: 'WhatsApp Your RM',
              subtitle: 'Account, payouts, investment queries',
              onTap: () => _openWhatsApp(
                context,
                phone: kRmPhone,
                preset: 'Hi, I have a question about my Growize investment: ',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(
    BuildContext context, {
    required String phone,
    required String preset,
  }) async {
    final waUri = Uri.parse(
      'https://wa.me/${phone.replaceAll('+', '')}'
      '?text=${Uri.encodeComponent(preset)}',
    );
    final ok = await launchUrl(waUri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp')),
      );
    }
  }
}

class _WhatsAppCta extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _WhatsAppCta({
    super.key,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.sand),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: _whatsappGreen,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: ArlColors.muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: ArlColors.muted,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }
}
