import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/arl_colors.dart';
import '../models/project_phase.dart';

class PhasesTimeline extends StatelessWidget {
  final List<ProjectPhase> phases;
  const PhasesTimeline({super.key, required this.phases});

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('MMM yyyy');
    return Column(
      children: List.generate(phases.length, (i) {
        final phase = phases[i];
        final isLast = i == phases.length - 1;
        Color dotColor;
        switch (phase.status) {
          case 'completed': dotColor = ArlColors.accent; break;
          case 'in_progress': dotColor = ArlColors.gold; break;
          default: dotColor = ArlColors.sand;
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      width: 12, height: 12,
                      decoration: BoxDecoration(
                        color: dotColor, shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [BoxShadow(
                          color: dotColor.withOpacity(0.4), blurRadius: 4,
                        )],
                      ),
                    ),
                    if (!isLast)
                      Expanded(child: Container(width: 2, color: ArlColors.sand)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: isLast ? 0 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(phase.name, style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600,
                        color: ArlColors.charcoal, fontFamily: 'Inter',
                      )),
                      if (phase.phaseDate != null)
                        Text(dateFmt.format(phase.phaseDate!),
                            style: const TextStyle(
                              fontSize: 12, color: ArlColors.muted, fontFamily: 'Inter',
                            )),
                      if (phase.subItems.isNotEmpty)
                        ...phase.subItems.map((item) {
                          final label = (item['label'] ?? item['text'] ?? item['name'] ?? '').toString();
                          if (label.isEmpty) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('• $label', style: const TextStyle(
                              fontSize: 12, color: ArlColors.muted, fontFamily: 'Inter',
                            )),
                          );
                        }),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
