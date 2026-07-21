import 'package:flutter/material.dart';

import '../../../../shared/failed_image.dart';

/// Renders an image from a `file:` URI. Default stub used on web, where
/// `dart:io` is unavailable. Conditional-imported by
/// `flutter_markdown_plus_renderer.dart` — the native implementation in
/// `file_image_loader_io.dart` replaces this on platforms with a filesystem.
Widget loadFileImage(Uri uri, String rawUri, String? alt) =>
    FailedImage(source: rawUri, label: alt);

/// Full-size zoomable viewer for a `file:` image, shown in the tap-to-zoom
/// dialog. Web stub: `file:` images can't be read, so it shows a bare centered
/// fallback (no zoom/rotate chrome).
Widget fileImageZoomViewer(Uri uri, String rawUri) =>
    const Center(child: FailedImage());
