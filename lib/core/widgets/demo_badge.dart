import 'package:flutter/material.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// Small "Sample" pill rendered next to demo data so investors can tell
/// what's real vs. placeholder. Disappears automatically once Supabase
/// returns at least one real row for the current investor.
class DemoBadge extends StatelessWidget {
  final bool show;
  final EdgeInsets margin;
  final String label;

  const DemoBadge({
    super.key,
    required this.show,
    this.margin = const EdgeInsets.only(left: 6),
    this.label = 'Sample',
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ArlColors.gold.withOpacity(0.18),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: ArlColors.gold.withOpacity(0.4),
          width: 0.6,
        ),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Inter',
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: Color(0xFF8C7300), // dark gold for legibility on gold-light
        ),
      ),
    );
  }
}

/// Top-of-screen banner shown once per session when ANY data on the
/// current screen is demo. Less noisy than per-row pills for screens
/// like the gallery where every card would have one.
class DemoModeBanner extends StatelessWidget {
  final bool show;

  const DemoModeBanner({super.key, required this.show});

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      color: ArlColors.gold.withOpacity(0.16),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: const Row(
        children: [
          Icon(Icons.science_outlined, size: 14, color: Color(0xFF8C7300)),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Showing sample data — your real investments will appear here once they sync.',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 11,
                color: Color(0xFF8C7300),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
