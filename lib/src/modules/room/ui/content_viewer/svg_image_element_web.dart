import 'dart:js_interop';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

// What draws an SVG as an image in the browser. The stand-in where there is
// no browser is in svg_image_element.dart.

/// Whether a browser is here to draw an SVG as an image.
const bool canDrawSvgInBrowser = true;

/// The browser would not draw an SVG image: it rejected the XML, or a
/// content security policy blocked the `data:` URL. The browser gives no
/// reason; its console names a policy that blocked it.
class SvgImageRejected implements Exception {
  const SvgImageRejected();

  @override
  String toString() => 'SvgImageRejected';
}

/// The SVG at [url], a `data:` URL, drawn by the browser in an HTML `<img>`
/// that fills this widget's box. The `<img>` loads once per widget state, so
/// a changed [url] is not loaded; `BrowserSvgPicture` keys this widget by its
/// URL, so a new one gets a fresh element.
///
/// The platform view and its DOM content let pointer input reach Flutter's
/// preview and zoom controls. The image's `error` event, from rejected XML or a
/// blocked URL, is reported through [onFailed] as [SvgImageRejected] while
/// this widget is mounted.
class SvgImageElement extends StatefulWidget {
  const SvgImageElement(this.url, {super.key, required this.onFailed});

  final String url;
  final void Function(Object error, StackTrace? stackTrace) onFailed;

  @override
  State<SvgImageElement> createState() => _SvgImageElementState();
}

class _SvgImageElementState extends State<SvgImageElement> {
  late final web.HTMLImageElement _image;
  late final JSFunction _onError;

  @override
  void initState() {
    super.initState();
    // Begin loading independently of platform-view creation and painting.
    // Flutter supplies the accessible label for the preview and zoom dialog.
    _image = web.HTMLImageElement()..alt = '';
    _image.style
      ..width = '100%'
      ..height = '100%'
      ..display = 'block'
      ..pointerEvents = 'none';
    _onError = (web.Event _) {
      if (mounted) widget.onFailed(const SvgImageRejected(), null);
    }.toJS;
    _image.addEventListener('error', _onError);
    _image.src = widget.url;
  }

  @override
  void dispose() {
    _image.removeEventListener('error', _onError);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView.fromTagName(
      tagName: 'div',
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
      onElementCreated: (element) {
        if (!mounted) return;
        final container = element as web.HTMLDivElement;
        // Flutter's hit-test behavior does not control DOM hit testing.
        container.style.pointerEvents = 'none';
        container.appendChild(_image);
      },
    );
  }
}
