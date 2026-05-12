import 'package:flutter/material.dart';
import 'package:arl_app/core/constants/supabase_constants.dart';

/// Top-of-screen banner shown when ARL_APP_MODE=demo. Sticky, non-dismissible.
/// Displays: "DEMO MODE — no real data is shown or saved."
///
/// Distinct from `DemoModeBanner` in demo_badge.dart, which is a per-screen
/// "Sample data" indicator triggered by `project.isDemo` rows. This one is
/// app-wide and triggered only by `ARL_APP_MODE=demo` env var.
class AppDemoModeBanner extends StatelessWidget {
  const AppDemoModeBanner({super.key});

  @override
  Widget build(BuildContext context) {
    if (!SupabaseConstants.isDemoMode) {
      return const SizedBox.shrink();
    }
    return Container(
      width: double.infinity,
      color: const Color(0xFFF2DC6B), // goldlight from CLAUDE.md
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.info_outline, size: 16, color: Color(0xFF3C5152)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'DEMO MODE — no real data is shown or saved.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3C5152),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
