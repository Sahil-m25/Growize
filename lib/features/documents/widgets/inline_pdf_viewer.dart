// Conditional export — web gets the iframe-based viewer, native keeps
// the SfPdfViewer path and never instantiates this widget.
export 'inline_pdf_viewer_web.dart'
    if (dart.library.io) 'inline_pdf_viewer_stub.dart';
