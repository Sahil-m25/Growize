import 'package:flutter/material.dart';
import 'package:arl_app/core/theme/arl_colors.dart';

/// A thin yellow strip pinned to the top of the main scaffold whenever
/// ARL_DEV_BYPASS=true in `.env`. Makes it impossible to forget the
/// bypass is on before shipping a build.
class DevBypassBanner extends StatelessWidget {
  const DevBypassBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: ArlColors.gold,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: 14, color: ArlColors.charcoal),
          SizedBox(width: 6),
          Text(
            'DEV BYPASS — auth disabled (ARL_DEV_BYPASS=true)',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ArlColors.charcoal,
              fontFamily: 'Inter',
            ),
          ),
        ],
      ),
    );
  }
}
