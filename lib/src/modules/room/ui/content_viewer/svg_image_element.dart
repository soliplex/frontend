import 'package:flutter/widgets.dart';

// What draws an SVG as an image where there is no browser. The browser's is
// in svg_image_element_web.dart.

/// Whether a browser is here to draw an SVG as an image.
const bool canDrawSvgInBrowser = false;

/// Stands in for the browser's `<img>`, which is not here: it draws nothing
/// and never reports [onFailed]. `SvgBody` asks for a browser picture only
/// where [canDrawSvgInBrowser], or where a test sets
/// `debugSvgInBrowserOverride`; such tests report its failure themselves.
class SvgImageElement extends StatelessWidget {
  const SvgImageElement(this.url, {super.key, required this.onFailed});

  final String url;
  final void Function(Object error, StackTrace? stackTrace) onFailed;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}
