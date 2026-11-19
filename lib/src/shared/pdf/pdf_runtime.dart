// Native implementation of the PDF runtime setup. The web one is in
// pdf_runtime_web.dart.

/// Prepares pdfrx before the first document opens. Nothing to do on native
/// platforms, where PDFium is linked into the app.
void ensurePdfRuntime() {}
