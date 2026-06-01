import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/documents/document_viewer_screen.dart';
import 'package:arl_app/features/documents/documents_provider.dart';
import 'package:arl_app/features/documents/models/document.dart';
import 'package:arl_app/features/documents/models/project_document.dart';
import 'package:arl_app/features/projects/models/investor_unit.dart';
import 'package:arl_app/features/projects/models/project.dart';
import 'package:arl_app/features/projects/projects_provider.dart';

/// Documents tab — surfaces two scopes in one scroll view:
///
///   1. Project Documents (migration 054) — single-source-of-truth
///      files (LLP agreements, brochures, quarterly reports) shared
///      across every investor with a non-zero allocation in the
///      project. Grouped by project so the eye can scan.
///
///   2. Personal Documents — the existing per-investor `documents`
///      table (KYC, contracts, payout receipts). Rendered with the
///      visibility-tier accordion already in production.
///
/// Both sections render their own skeleton / empty / error states;
/// the screen shell always renders so the back-button is reachable.
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocSection {
  final String title;
  final IconData icon;
  final Color color;
  final List<InvestorDocument> items;
  const _DocSection(this.title, this.icon, this.color, this.items);
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  /// Tracks which Personal-tier accordions are open. Project Documents
  /// section is permanently expanded — there's typically only a handful
  /// of files per project so the click-to-expand affordance adds noise.
  final Set<int> _open = {0};

  List<_DocSection> _group(List<InvestorDocument> docs) {
    final common = <InvestorDocument>[];
    final project = <InvestorDocument>[];
    final investor = <InvestorDocument>[];
    for (final d in docs) {
      switch (d.visibility) {
        case 'common':
          common.add(d);
          break;
        case 'project':
          project.add(d);
          break;
        default:
          investor.add(d);
      }
    }
    return [
      _DocSection('Common', Icons.public, ArlColors.primary, common),
      _DocSection('My Projects', Icons.eco, ArlColors.accent, project),
      _DocSection(
          'My Documents', Icons.folder_special, ArlColors.gold, investor),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final personalAsync = ref.watch(documentsProvider);
    final projectDocsAsync = ref.watch(allProjectDocumentsProvider);
    final projects = ref.watch(projectsProvider).valueOrNull ?? const <Project>[];
    final units =
        ref.watch(investorUnitsListProvider).valueOrNull ?? const <InvestorUnit>[];

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            // Header row — back button + page title.
            Row(
              children: [
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(Icons.arrow_back,
                      color: ArlColors.charcoal, size: 20),
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(RouteNames.home),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Documents',
                  style: TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ---- Section 1: Project Documents ----
            const _SectionChip(
              label: 'PROJECT DOCUMENTS',
              borderColor: ArlColors.gold,
              textColor: ArlColors.primary,
            ),
            const SizedBox(height: 6),
            const Text(
              'Available to all investors in your projects',
              style: TextStyle(color: ArlColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            _ProjectDocumentsBlock(
              docsAsync: projectDocsAsync,
              projects: projects,
              units: units,
            ),

            const SizedBox(height: 24),

            // ---- Section 2: Personal Documents ----
            const _SectionChip(
              label: 'PERSONAL DOCUMENTS',
              borderColor: ArlColors.sand,
              textColor: ArlColors.muted,
            ),
            const SizedBox(height: 6),
            const Text(
              'KYC, contracts, payouts',
              style: TextStyle(color: ArlColors.muted, fontSize: 11),
            ),
            const SizedBox(height: 12),
            if (personalAsync.valueOrNull == null)
              ..._skeletonRows()
            else
              ..._personalRows(personalAsync.value!),
          ],
        ),
      ),
    );
  }

  List<Widget> _personalRows(List<InvestorDocument> docs) {
    final sections = _group(docs);
    if (sections.every((s) => s.items.isEmpty)) return [_personalEmptyState()];
    final rows = <Widget>[];
    for (int i = 0; i < sections.length; i++) {
      rows.add(_Accordion(
        section: sections[i],
        isOpen: _open.contains(i),
        onTap: () => setState(() {
          _open.contains(i) ? _open.remove(i) : _open.add(i);
        }),
      ));
      rows.add(const SizedBox(height: 8));
    }
    return rows;
  }

  List<Widget> _skeletonRows() {
    return List.generate(3, (_) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          height: 64,
          decoration: BoxDecoration(
            color: ArlColors.sand.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      );
    });
  }

  Widget _personalEmptyState() => Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.sand),
        ),
        child: const Column(
          children: [
            Icon(Icons.folder_open, color: ArlColors.muted, size: 36),
            SizedBox(height: 8),
            Text(
              'No documents yet',
              style: TextStyle(
                color: ArlColors.charcoal,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Your agreements and KYC documents will appear here once uploaded.',
              textAlign: TextAlign.center,
              style: TextStyle(color: ArlColors.muted, fontSize: 11),
            ),
          ],
        ),
      );
}

/// Gold/sand-bordered section chip — matches the HTML prototype's
/// uppercase letter-spaced label pills.
class _SectionChip extends StatelessWidget {
  final String label;
  final Color borderColor;
  final Color textColor;

  const _SectionChip({
    required this.label,
    required this.borderColor,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}

/// Renders the Project Documents section — handles loading, error,
/// empty, and "grouped by project" success states.
class _ProjectDocumentsBlock extends StatelessWidget {
  final AsyncValue<List<ProjectDocument>> docsAsync;
  final List<Project> projects;
  final List<InvestorUnit> units;

  const _ProjectDocumentsBlock({
    required this.docsAsync,
    required this.projects,
    required this.units,
  });

  String _projectName(String projectId) {
    for (final p in projects) {
      if (p.id == projectId) return p.name;
    }
    return 'Project';
  }

  /// Sum of issued units for the signed-in investor in this project.
  /// Multiple allocation rows per (investor, project) are possible —
  /// the spec around `investor_units` calls this out — so we add them
  /// all up rather than picking the first.
  int _unitsFor(String projectId) {
    var total = 0;
    for (final u in units) {
      if (u.projectId == projectId) total += u.issuedUnits;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    return docsAsync.when(
      loading: () => Column(
        children: List.generate(2, (_) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: ArlColors.sand.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(15),
              ),
            ),
          );
        }),
      ),
      error: (_, __) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.sand),
        ),
        child: const Row(
          children: [
            Icon(Icons.cloud_off_outlined, color: ArlColors.muted, size: 16),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Could not load project documents. Pull to refresh.',
                style: TextStyle(color: ArlColors.muted, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      data: (docs) {
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: ArlColors.sand),
            ),
            child: const Center(
              child: Text(
                'No project documents yet',
                style: TextStyle(
                  color: ArlColors.muted,
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          );
        }

        // Group by project_id. Preserve doc ordering (which the server
        // already sorted by sort_order, then uploaded_at desc).
        final byProject = <String, List<ProjectDocument>>{};
        for (final d in docs) {
          byProject.putIfAbsent(d.projectId, () => <ProjectDocument>[]).add(d);
        }
        // Sort project groups by name so the order is stable.
        final entries = byProject.entries.toList()
          ..sort((a, b) =>
              _projectName(a.key).compareTo(_projectName(b.key)));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              _ProjectGroupHeader(
                projectName: _projectName(entries[i].key),
                unitCount: _unitsFor(entries[i].key),
              ),
              const SizedBox(height: 8),
              for (final doc in entries[i].value) ...[
                _ProjectDocRow(doc: doc),
                const SizedBox(height: 8),
              ],
              if (i != entries.length - 1) const SizedBox(height: 8),
            ],
          ],
        );
      },
    );
  }
}

class _ProjectGroupHeader extends StatelessWidget {
  final String projectName;
  final int unitCount;

  const _ProjectGroupHeader({
    required this.projectName,
    required this.unitCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 6,
          height: 18,
          decoration: BoxDecoration(
            color: ArlColors.accent,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            projectName,
            style: const TextStyle(
              color: ArlColors.charcoal,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (unitCount > 0)
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: ArlColors.gold.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$unitCount ${unitCount == 1 ? 'unit' : 'units'}',
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProjectDocRow extends StatelessWidget {
  final ProjectDocument doc;
  const _ProjectDocRow({required this.doc});

  void _open(BuildContext context) {
    if (doc.signedUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document URL unavailable')),
      );
      return;
    }
    // The viewer accepts an InvestorDocument. Project docs map cleanly
    // onto that shape (visibility=project, projectId set) — pass an
    // adapter so we don't have to fork the viewer for two scopes.
    final adapter = InvestorDocument(
      id: doc.id,
      name: doc.title,
      category: doc.category,
      visibility: 'project',
      projectId: doc.projectId,
      signedUrl: doc.signedUrl,
      uploadedAt: doc.uploadedAt,
    );
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(
          documentId: doc.id,
          preloaded: adapter,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM dd, yyyy').format(doc.uploadedAt);
    return InkWell(
      onTap: () => _open(context),
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: ArlColors.sand, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: ArlColors.accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.description_outlined,
                  color: ArlColors.accent, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ArlColors.charcoal,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _CategoryPill(category: doc.category),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          dateStr,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ArlColors.muted,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Icon(Icons.visibility_outlined,
                color: ArlColors.accent, size: 16),
          ],
        ),
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String category;
  const _CategoryPill({required this.category});

  String _label(String c) {
    if (c.isEmpty) return 'GENERAL';
    return c.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: ArlColors.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label(category),
        style: const TextStyle(
          color: ArlColors.accent,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

class _Accordion extends StatelessWidget {
  final _DocSection section;
  final bool isOpen;
  final VoidCallback onTap;
  const _Accordion(
      {required this.section, required this.isOpen, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: ArlColors.sand, width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: section.color.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(section.icon, color: section.color, size: 16),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        section.title,
                        style: const TextStyle(
                          color: ArlColors.charcoal,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '${section.items.length} ${section.items.length == 1 ? 'file' : 'files'}',
                        style: const TextStyle(
                          color: ArlColors.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: isOpen ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: const Icon(Icons.keyboard_arrow_down,
                      color: ArlColors.muted, size: 18),
                ),
              ],
            ),
          ),
        ),
        if (isOpen) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: section.items.isEmpty
                ? Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: ArlColors.sand, width: 1),
                    ),
                    child: const Text(
                      'No documents in this section yet.',
                      style: TextStyle(color: ArlColors.muted, fontSize: 11),
                    ),
                  )
                : Column(
                    children: [
                      for (final it in section.items) ...[
                        _DocRow(item: it, color: section.color),
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
          ),
        ],
      ],
    );
  }
}

class _DocRow extends StatelessWidget {
  final InvestorDocument item;
  final Color color;
  const _DocRow({required this.item, required this.color});

  String _formatMeta() {
    final parts = <String>[];
    if (item.uploadedAt != null) {
      parts.add(DateFormat('MMM dd, yyyy').format(item.uploadedAt!));
    }
    if (item.fileSizeKb != null && item.fileSizeKb! > 0) {
      final kb = item.fileSizeKb!;
      parts.add(kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb KB');
    }
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  Future<void> _open(BuildContext context) async {
    if (item.signedUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Document URL unavailable')),
      );
      return;
    }
    // Push the in-app document viewer instead of handing off to the
    // OS browser. The viewer enforces screenshot prevention while open
    // (Android FLAG_SECURE, iOS blur during background / recording).
    // Deep-linkable via `/document-viewer/<id>`; we also pass the
    // doc as `extra` so the viewer doesn't have to re-resolve from
    // the cache when the user comes from the list.
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(
          documentId: item.id,
          preloaded: item,
        ),
        fullscreenDialog: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: ArlColors.sand, width: 1),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.description, color: color, size: 14),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  style: const TextStyle(
                    color: ArlColors.charcoal,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatMeta(),
                  style: const TextStyle(
                    color: ArlColors.muted,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(Icons.visibility_outlined, color: color, size: 16),
            onPressed: () => _open(context),
          ),
        ],
      ),
    );
  }
}
