import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../svg_root_size.dart';
import 'svg_fit.dart';
import 'svg_image_element.dart'
    if (dart.library.js_interop) 'svg_image_element_web.dart';

export 'svg_image_element.dart'
    if (dart.library.js_interop) 'svg_image_element_web.dart'
    show canDrawSvgInBrowser;

/// [svg] drawn by the browser, as an image in an HTML `<img>`, so the
/// browser applies its `<style>` sheets, markers, filters and
/// `<foreignObject>` content. Drawn as an image, the SVG runs no script and
/// fetches nothing external.
///
/// The picture is sized from [svgRootSize] and laid out by [fitSvg], and the
/// `<img>` fills exactly the picture's box: the browser's own size for an SVG
/// image (300 x 150 for many roots, rounded to whole pixels, sometimes 0)
/// never enters layout. In an `<img>` of another shape, an SVG without a
/// viewBox is stretched, so the box keeps the picture's shape.
///
/// The element also loads at zero area, so layout cannot suppress rejection
/// of the SVG. [onFailed] is called outside build when the browser rejects it
/// (see `SvgImageRejected`).
class BrowserSvgPicture extends StatelessWidget {
  const BrowserSvgPicture(this.svg, {super.key, required this.onFailed});

  final String svg;
  final void Function(Object error, StackTrace? stackTrace) onFailed;

  @override
  Widget build(BuildContext context) {
    final size = svgRootSize(svg);
    late final url = Uri.dataFromString(
      svg,
      mimeType: 'image/svg+xml',
      encoding: utf8,
    ).toString();
    return LayoutBuilder(
      builder: (context, constraints) {
        final (:box, :picture) = fitSvg(size, constraints);
        return SizedBox.fromSize(
          size: box,
          child: Center(
            child: SizedBox.fromSize(
              size: picture,
              child: SvgImageElement(
                url,
                key: ValueKey(url),
                onFailed: onFailed,
              ),
            ),
          ),
        );
      },
    );
  }
}
