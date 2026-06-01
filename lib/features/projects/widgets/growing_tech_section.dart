import 'package:flutter/material.dart';

import '../../../core/theme/arl_colors.dart';

/// Lightweight value type carrying the data the [GrowingTechSection]
/// widget needs. Lives next to the widget to avoid creating yet another
/// model file for what is essentially a presentation bag.
class GrowingTech {
  final String method;
  final String methodSubtitle;
  final int waterSavedPct;
  final String annualYield;
  final int cyclesPerYear;
  final bool pesticideFree;
  final bool climateControlled;
  final String techStack;
  final List<String> certifications;

  const GrowingTech({
    required this.method,
    required this.methodSubtitle,
    required this.waterSavedPct,
    required this.annualYield,
    required this.cyclesPerYear,
    this.pesticideFree = true,
    this.climateControlled = true,
    this.techStack = '',
    this.certifications = const [],
  });

  /// EKA — Aeroponic / 95% / 32 kg/m² / 8 cycles.
  static const eka = GrowingTech(
    method: 'Aeroponic',
    methodSubtitle: 'Soil-free root system',
    waterSavedPct: 95,
    annualYield: '32 kg/m²',
    cyclesPerYear: 8,
    techStack: 'IoT sensors · auto-misting · ML-based nutrient dosing',
    certifications: ['FSSAI', 'Organic', 'GAP'],
  );

  /// Sunrise Orchards — Hydroponic / 88% / 25 kg/m² / 6 cycles.
  static const sunriseOrchards = GrowingTech(
    method: 'Hydroponic',
    methodSubtitle: 'NFT + DWC channels',
    waterSavedPct: 88,
    annualYield: '25 kg/m²',
    cyclesPerYear: 6,
    techStack: 'pH controllers · EC monitoring · LED supplementary lighting',
    certifications: ['FSSAI', 'GAP'],
  );

  /// Verdant Acres — Vertical Aeroponic / 96% / 38 kg/m² / 9 cycles.
  static const verdantAcres = GrowingTech(
    method: 'Vertical Aeroponic',
    methodSubtitle: 'Stacked towers, soil-free',
    waterSavedPct: 96,
    annualYield: '38 kg/m²',
    cyclesPerYear: 9,
    techStack: 'Automated towers · climate-controlled · spray cycles every 6 min',
    certifications: ['FSSAI', 'Organic', 'GAP'],
  );

  /// Pick demo defaults based on the project initials. Falls back to
  /// EKA when we don't have a curated profile yet.
  static GrowingTech forProject({
    required String projectId,
    required String initials,
  }) {
    final id = projectId.replaceAll(RegExp(r'^demo:'), '').toLowerCase();
    if (id == 'gv' || initials.toUpperCase() == 'GV') return eka;
    if (id == 'so' || initials.toUpperCase() == 'SO') {
      return sunriseOrchards;
    }
    if (id == 'va' || initials.toUpperCase() == 'VA') return verdantAcres;
    return eka;
  }
}

/// Growing Technology card — 2x3 stat grid + tech stack line + cert
/// chips. Mirrors the v3 R3 block moved into the Location/View Area
/// page in the HTML mockup.
class GrowingTechSection extends StatelessWidget {
  final GrowingTech tech;
  const GrowingTechSection({super.key, required this.tech});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 16, color: ArlColors.primary),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Growing Technology',
                  style: TextStyle(
                    color: ArlColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: ArlColors.accent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  tech.method,
                  style: const TextStyle(
                    color: ArlColors.accent,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.7,
            children: [
              _tile(
                icon: Icons.eco,
                label: 'Method',
                value: tech.method,
                subtitle: tech.methodSubtitle,
              ),
              _tile(
                icon: Icons.water_drop_outlined,
                label: 'Water Saved',
                value: '${tech.waterSavedPct}%',
                subtitle: 'vs traditional',
              ),
              _tile(
                icon: Icons.trending_up,
                label: 'Annual Yield',
                value: tech.annualYield,
                subtitle: '10× higher',
              ),
              _tile(
                icon: Icons.refresh,
                label: 'Cycles',
                value: '${tech.cyclesPerYear} / yr',
                subtitle: 'vs 2–3 traditional',
              ),
              _badgeTile(
                icon: Icons.spa_outlined,
                label: 'Pesticide-Free',
                active: tech.pesticideFree,
              ),
              _badgeTile(
                icon: Icons.thermostat,
                label: 'Climate Controlled',
                active: tech.climateControlled,
              ),
            ],
          ),
          if (tech.techStack.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'TECH STACK',
              style: TextStyle(
                color: ArlColors.muted,
                fontSize: 10,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              tech.techStack,
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ],
          if (tech.certifications.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tech.certifications
                  .map(
                    (c) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: ArlColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: ArlColors.primary.withOpacity(0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.verified_outlined,
                              size: 12, color: ArlColors.primary),
                          const SizedBox(width: 4),
                          Text(
                            c,
                            style: const TextStyle(
                              color: ArlColors.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String label,
    required String value,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ArlColors.sand.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ArlColors.sand),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: ArlColors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.toUpperCase(),
                  style: const TextStyle(
                    color: ArlColors.muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              color: ArlColors.muted,
              fontSize: 9,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badgeTile({
    required IconData icon,
    required String label,
    required bool active,
  }) {
    final color = active ? ArlColors.accent : ArlColors.muted;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active
            ? ArlColors.accent.withOpacity(0.1)
            : ArlColors.sand.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: active
              ? ArlColors.accent.withOpacity(0.3)
              : ArlColors.sand,
        ),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (active)
            Icon(Icons.check_circle, size: 14, color: color),
        ],
      ),
    );
  }
}
