import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/legal/legal_content.dart';

/// Shared layout for the Privacy Policy and Terms of Service screens.
/// Both renders identical chrome — back affordance, banner reminding the
/// reader that the text is a template pending legal review, and a
/// scrollable monospace-friendly body. The actual copy lives in
/// [LegalDocs] so the screens stay layout-only.
class LegalDocumentScreen extends StatelessWidget {
  final String title;
  final String body;
  const LegalDocumentScreen({
    super.key,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.arrow_back,
                      color: ArlColors.charcoal,
                      size: 20,
                    ),
                    onPressed: () {
                      // Prefer pop so we don't blow away the back stack
                      // when the screen is opened from the setup wizard.
                      if (context.canPop()) {
                        context.pop();
                      } else {
                        context.go(RouteNames.profile);
                      }
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: ArlColors.charcoal,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: ArlColors.gold.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: ArlColors.gold.withOpacity(0.4),
                        ),
                      ),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: ArlColors.gold,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              LegalDocs.templateBanner,
                              style: TextStyle(
                                color: ArlColors.charcoal,
                                fontSize: 11,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: ArlColors.sand),
                      ),
                      child: SelectableText(
                        body,
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 13,
                          height: 1.55,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalDocumentScreen(
        title: LegalDocs.privacyTitle,
        body: LegalDocs.privacyBody,
      );
}

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => const LegalDocumentScreen(
        title: LegalDocs.termsTitle,
        body: LegalDocs.termsBody,
      );
}
