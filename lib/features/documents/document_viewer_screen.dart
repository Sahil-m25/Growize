// Conditional import: dart.library.io is true on native (Android/iOS/desktop),
// false on web. Web gets no-op stubs; all usages are already guarded by kIsWeb.
import 'package:arl_app/core/utils/io_types_web.dart'
    if (dart.library.io) 'package:arl_app/core/utils/io_types.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:screen_protector/screen_protector.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import 'package:arl_app/core/theme/arl_colors.dart';
import 'package:arl_app/features/documents/documents_provider.dart';
import 'package:arl_app/features/documents/models/document.dart';

/// Full-screen in-app document viewer.
///
/// Renders PDFs (via Syncfusion) and images (via CachedNetworkImage inside
/// an InteractiveViewer for pinch-zoom). Unknown types degrade to a
/// "download to view" fallback so the investor still gets a way to read
/// the file without bouncing out to the OS browser.
///
/// Screenshot / screen-record prevention is enabled in initState on
/// Android + iOS via `screen_protector` and disabled in dispose so it
/// doesn't leak into the rest of the app. On web the protection is
/// not available (browser platform limitation) — documented in the
/// decision log.
class DocumentViewerScreen extends ConsumerStatefulWidget {
  /// Document id (matches `documents.id` in Supabase). Used to look up
  /// the row from `documentsProvider` so the screen is deep-linkable —
  /// e.g. `/document-viewer/<uuid>`.
  final String documentId;

  /// Optional pre-loaded doc — passed when navigating from the list so
  /// we skip the provider lookup. Falls back to `documentsProvider` if
  /// null (deep-link case).
  final InvestorDocument? preloaded;

  const DocumentViewerScreen({
    super.key,
    required this.documentId,
    this.preloaded,
  });

  @override
  ConsumerState<DocumentViewerScreen> createState() =>
      _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends ConsumerState<DocumentViewerScreen> {
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _enableScreenProtection();
  }

  @override
  void dispose() {
    _disableScreenProtection();
    super.dispose();
  }

  Future<void> _enableScreenProtection() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await ScreenProtector.preventScreenshotOn();
      } else if (Platform.isIOS) {
        // iOS: blanks the snapshot taken when the app is backgrounded
        // and obscures the screen during screen recording.
        await ScreenProtector.protectDataLeakageOn();
        await ScreenProtector.protectDataLeakageWithBlur();
      }
    } catch (_) {
      // Best-effort — never crash the viewer because protection failed.
    }
  }

  Future<void> _disableScreenProtection() async {
    if (kIsWeb) return;
    try {
      if (Platform.isAndroid) {
        await ScreenProtector.preventScreenshotOff();
      } else if (Platform.isIOS) {
        await ScreenProtector.protectDataLeakageOff();
      }
    } catch (_) {
      // Ignore — disposing.
    }
  }

  /// Look up the doc from the provider cache when no preloaded copy
  /// was passed (e.g. a deep-link landed straight on this route).
  InvestorDocument? _resolveDoc() {
    if (widget.preloaded != null) return widget.preloaded;
    final list = ref.read(documentsProvider).valueOrNull;
    if (list == null) return null;
    for (final d in list) {
      if (d.id == widget.documentId) return d;
    }
    return null;
  }

  String _extOf(InvestorDocument doc) {
    // The signed URL has the storage path embedded — fall back to the
    // doc name if the URL is empty (offline cache miss).
    final source = doc.signedUrl.isNotEmpty ? doc.signedUrl : doc.name;
    final qIdx = source.indexOf('?');
    final clean = qIdx >= 0 ? source.substring(0, qIdx) : source;
    final dotIdx = clean.lastIndexOf('.');
    if (dotIdx < 0 || dotIdx == clean.length - 1) return '';
    return clean.substring(dotIdx + 1).toLowerCase();
  }

  bool _isImage(String ext) =>
      ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'webp' ||
      ext == 'gif' || ext == 'bmp';

  bool _isPdf(String ext) => ext == 'pdf';

  Future<void> _download(InvestorDocument doc) async {
    if (_downloading) return;
    if (doc.signedUrl.isEmpty) {
      _toast('Document URL unavailable');
      return;
    }
    setState(() => _downloading = true);
    try {
      final res = await http.get(Uri.parse(doc.signedUrl));
      if (res.statusCode != 200) {
        _toast('Download failed (${res.statusCode})');
        return;
      }
      if (kIsWeb) {
        // On web we can't write to disk silently — keep the bytes in
        // memory for now and just confirm. A future enhancement could
        // wire an HTML anchor with a blob URL for browser download.
        _toast('Document loaded (${(res.bodyBytes.length / 1024).round()} KB)');
        return;
      }
      final dir = await getApplicationDocumentsDirectory();
      final safeName = doc.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${dir.path}${Platform.pathSeparator}$safeName');
      await file.writeAsBytes(res.bodyBytes, flush: true);
      _toast('Saved to in-app library');
    } catch (e) {
      _toast('Download error');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final doc = _resolveDoc();

    return Scaffold(
      backgroundColor: ArlColors.cream,
      appBar: AppBar(
        backgroundColor: ArlColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => context.canPop() ? context.pop() : context.go('/documents'),
        ),
        title: Text(
          doc?.name ?? 'Document',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          if (doc != null)
            IconButton(
              icon: _downloading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download_outlined, size: 20),
              tooltip: 'Save to in-app library',
              onPressed: _downloading ? null : () => _download(doc),
            ),
        ],
      ),
      body: doc == null ? _missing() : _body(doc),
    );
  }

  Widget _body(InvestorDocument doc) {
    if (doc.signedUrl.isEmpty) {
      return _fallback(
        'Document URL unavailable.',
        'We could not generate a secure link for this file. Pull-to-refresh on the Documents tab and try again.',
        doc,
      );
    }
    final ext = _extOf(doc);
    if (_isPdf(ext)) return _PdfBody(url: doc.signedUrl, doc: doc);
    if (_isImage(ext)) return _imageBody(doc);
    return _fallback(
      'Preview not supported',
      'This document type (.${ext.isEmpty ? 'unknown' : ext}) can\'t be previewed in-app. Tap "Download" above to save a copy to your in-app library.',
      doc,
    );
  }

  Widget _imageBody(InvestorDocument doc) {
    return InteractiveViewer(
      minScale: 1,
      maxScale: 5,
      child: Center(
        child: CachedNetworkImage(
          imageUrl: doc.signedUrl,
          fit: BoxFit.contain,
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(color: ArlColors.accent),
          ),
          errorWidget: (_, __, ___) => _fallback(
            'Could not load image',
            'The network request failed. Check connectivity and try again.',
            doc,
          ),
        ),
      ),
    );
  }

  Widget _missing() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.help_outline,
                  color: ArlColors.muted, size: 36),
              const SizedBox(height: 12),
              const Text(
                'Document not found',
                style: TextStyle(
                  color: ArlColors.charcoal,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'It may have been removed or your library is still loading.',
                textAlign: TextAlign.center,
                style: TextStyle(color: ArlColors.muted, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () =>
                    context.canPop() ? context.pop() : context.go('/documents'),
                child: const Text('Back to Documents'),
              ),
            ],
          ),
        ),
      );

  Widget _fallback(String title, String body, InvestorDocument doc) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.description_outlined,
                color: ArlColors.muted, size: 36),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                color: ArlColors.charcoal,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              textAlign: TextAlign.center,
              style: const TextStyle(color: ArlColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: ArlColors.accent,
                foregroundColor: Colors.white,
              ),
              onPressed: _downloading ? null : () => _download(doc),
              icon: const Icon(Icons.download_outlined, size: 16),
              label: const Text('Download'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Encapsulates the PDF render path so we can retry the signed URL
/// once if the first load fails (URL may have expired between the
/// list fetch and the user tapping the tile). Holds local state for
/// the loader progress.
class _PdfBody extends ConsumerStatefulWidget {
  final String url;
  final InvestorDocument doc;
  const _PdfBody({required this.url, required this.doc});

  @override
  ConsumerState<_PdfBody> createState() => _PdfBodyState();
}

class _PdfBodyState extends ConsumerState<_PdfBody> {
  late String _url;
  bool _retried = false;

  @override
  void initState() {
    super.initState();
    _url = widget.url;
  }

  Future<void> _retry() async {
    if (_retried) return;
    _retried = true;
    // Force a refresh of the documents list so signed URLs get
    // regenerated, then re-pick this doc.
    ref.invalidate(documentsProvider);
    try {
      final list = await ref.read(documentsProvider.future);
      InvestorDocument? fresh;
      for (final d in list) {
        if (d.id == widget.doc.id) {
          fresh = d;
          break;
        }
      }
      if (fresh != null && fresh.signedUrl.isNotEmpty && mounted) {
        setState(() => _url = fresh!.signedUrl);
      }
    } catch (_) {
      // Refresh failed — Syncfusion will surface the original error.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SfPdfViewer.network(
      _url,
      enableTextSelection: false,
      canShowScrollHead: true,
      canShowScrollStatus: true,
      onDocumentLoadFailed: (details) {
        if (!_retried) {
          _retry();
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not load PDF: ${details.error}')),
          );
        }
      },
    );
  }
}
