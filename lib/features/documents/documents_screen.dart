import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:arl_app/core/navigation/route_names.dart';
import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/documents/documents_provider.dart';
import 'package:arl_app/features/documents/models/document.dart';

class _DocSection {
  final String title;
  final IconData icon;
  final Color color;
  final List<InvestorDocument> items;
  const _DocSection(this.title, this.icon, this.color, this.items);
}

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final Set<int> _open = {0};

  /// Group docs by visibility tier (migration 032/033). Renders
  /// Common → My Projects → My Documents in fixed order so the
  /// layout is stable as docs come and go. Tiers with zero items
  /// are still emitted so the section's empty-state can render.
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
    final docsAsync = ref.watch(documentsProvider);
    // Always render the screen shell (header + scrollable). Body swaps
    // between cached data, empty-state, and skeleton — never blank.
    final docs = docsAsync.valueOrNull;

    return Scaffold(
      backgroundColor: ArlColors.cream,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
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
            if (docs == null) ..._skeletonRows() else ..._dataRows(docs),
          ],
        ),
      ),
    );
  }

  List<Widget> _dataRows(List<InvestorDocument> docs) {
    final sections = _group(docs);
    if (sections.every((s) => s.items.isEmpty)) return [_emptyState()];
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

  Widget _emptyState() => Container(
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
    final uri = Uri.tryParse(item.signedUrl);
    if (uri == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid document URL')),
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open document')),
      );
    }
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
