import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/arl_colors.dart';
import '../models/project.dart';

class ProjectCard extends StatelessWidget {
  final Project project;
  const ProjectCard({super.key, required this.project});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.go('/projects/${project.id}'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6)],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: ArlColors.primary.withValues(alpha: 0.1),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: const Center(
                child: Icon(Icons.agriculture, size: 48, color: ArlColors.primary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(project.name, style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600,
                          color: ArlColors.charcoal, fontFamily: 'Inter',
                        )),
                      ),
                      _StatusChip(status: project.status),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text('${project.cropType} • ${project.location}',
                      style: const TextStyle(fontSize: 12, color: ArlColors.muted, fontFamily: 'Inter')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg; Color fg;
    switch (status) {
      case 'active':
        bg = const Color(0xFFDCFCE7); fg = const Color(0xFF166534);
        break;
      case 'completed':
        bg = const Color(0xFFE0E7FF); fg = const Color(0xFF3730A3);
        break;
      default:
        bg = const Color(0xFFFEF9C3); fg = const Color(0xFF854D0E);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(
        fontSize: 11, fontWeight: FontWeight.w600, color: fg, fontFamily: 'Inter',
      )),
    );
  }
}
