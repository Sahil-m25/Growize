import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// B.T7: Full-screen blocker shown when the app version is too old.
/// The user must update before proceeding.
class ForceUpdateScreen extends StatelessWidget {
  final String currentVersion;
  final String minimumVersion;

  const ForceUpdateScreen({
    super.key,
    required this.currentVersion,
    required this.minimumVersion,
  });

  Future<void> _openPlayStore() async {
    final playStoreUrl =
        Uri.parse('https://play.google.com/store/apps/details?id=com.arl.app');
    if (await canLaunchUrl(playStoreUrl)) {
      await launchUrl(playStoreUrl, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Center(
                  child: Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [ArlColors.primary, ArlColors.accent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: ArlColors.primary.withOpacity(0.25),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.system_update,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                const Text(
                  'Update required',
                  style: TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'A newer version of Growize is available. Please update to continue.',
                  style: TextStyle(
                    color: ArlColors.muted,
                    fontSize: 14,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: ArlColors.sand),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Current version',
                            style: TextStyle(
                              color: ArlColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            currentVersion,
                            style: const TextStyle(
                              color: ArlColors.charcoal,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Required version',
                            style: TextStyle(
                              color: ArlColors.muted,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            minimumVersion,
                            style: const TextStyle(
                              color: ArlColors.earth,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _openPlayStore,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ArlColors.primary,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Update now',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
