// Web-only. This file is only imported on Flutter web via the conditional
// export in inline_pdf_viewer.dart — never compiled on Android/iOS.
// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

import 'package:arl_app/core/theme/arl_colors.dart';

/// Renders a PDF URL inside the Flutter web app using a same-origin iframe
/// that hosts PDF.js (web/pdf_viewer.html).
///
/// Why not a direct iframe to the Supabase URL?
/// Supabase storage returns X-Frame-Options: DENY on all responses, so Chrome
/// blocks any attempt to embed the URL in an iframe.
///
/// Why PDF.js via same-origin iframe?
/// - The iframe src is /pdf_viewer.html (our own domain) — Chrome allows it.
/// - PDF.js inside fetches the signed URL via XHR. Supabase sets
///   Access-Control-Allow-Origin: * on signed URLs, so the fetch succeeds.
/// - The PDF is rendered on canvas — no download prompt, stays in the window.
class InlinePdfViewer extends StatefulWidget {
  final String url;
  const InlinePdfViewer({super.key, required this.url});

  @override
  State<InlinePdfViewer> createState() => _InlinePdfViewerState();
}

class _InlinePdfViewerState extends State<InlinePdfViewer> {
  late final String _viewId;

  @override
  void initState() {
    super.initState();
    // Each viewer instance needs a unique view-type string; collisions
    // cause "already registered" errors if the user opens two documents.
    _viewId =
        'growize-pdf-${widget.url.hashCode}-${DateTime.now().microsecondsSinceEpoch}';

    ui.platformViewRegistry.registerViewFactory(_viewId, (int viewId) {
      final encoded = Uri.encodeComponent(widget.url);
      return html.IFrameElement()
        ..src = '/pdf_viewer.html?url=$encoded'
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allowFullscreen = false
        ..setAttribute('sandbox', 'allow-scripts allow-same-origin');
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: ArlColors.cream,
      child: HtmlElementView(viewType: _viewId),
    );
  }
}
