// The picture's layout and its element's identity are tested on the VM,
// where the element is the stand-in this file imports; in a browser the
// picture builds the web element instead, which these tests cannot find.
// What the browser draws, and its failures, are checked in the browser.
@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/browser_svg_picture.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_image_element.dart';

const _svg = '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="60">'
    '<rect width="120" height="60" fill="red"/></svg>';
const _tall = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 30 100">'
    '</svg>';

const _pictureKey = ValueKey('picture');

String _urlOf(String svg) =>
    Uri.dataFromString(svg, mimeType: 'image/svg+xml', encoding: utf8)
        .toString();

/// [svg]'s picture as an inline SvgBody lays it out: the column's width,
/// stretched, and at most 400 high.
Widget _inline(String svg, {double width = 600}) => MaterialApp(
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 400),
            child: BrowserSvgPicture(
              svg,
              key: _pictureKey,
              onFailed: (_, __) {},
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('explicit zero suppresses painting even with a viewBox',
      (tester) async {
    await tester.pumpWidget(
      _inline('<svg width="0px" viewBox="0 0 120 60"></svg>'),
    );

    expect(tester.getSize(find.byKey(_pictureKey)), const Size(600, 0));
    expect(tester.getSize(find.byType(SvgImageElement)), Size.zero);
  });

  testWidgets('collapse and expansion keep the same image attempt',
      (tester) async {
    await tester.pumpWidget(_inline(_svg));
    final image = find.byType(SvgImageElement);
    final element = tester.element(image);

    await tester.pumpWidget(_inline(_svg, width: 0));
    expect(tester.getSize(image), Size.zero);
    expect(tester.element(image), same(element));

    await tester.pumpWidget(_inline(_svg));
    expect(tester.getSize(image), const Size(600, 300));
    expect(tester.element(image), same(element));
  });

  testWidgets('a positive fractional side still mounts the image',
      (tester) async {
    await tester.pumpWidget(
      _inline('<svg width="0.1" height="10" viewBox="0 0 1 100"></svg>'),
    );

    // 0.1 x 10 scaled to the 400 height cap: 4 x 400.
    expect(tester.getSize(find.byType(SvgImageElement)), const Size(4, 400));
  });

  testWidgets('gives the element the SVG as a data URL', (tester) async {
    // A `#` would end the URL's data at a fragment unless encoded.
    const svg = '<svg xmlns="http://www.w3.org/2000/svg" width="120" '
        'height="60"><text fill="#f00">Ünïcødé ✓</text></svg>';
    await tester.pumpWidget(_inline(svg));

    final element =
        tester.widget<SvgImageElement>(find.byType(SvgImageElement));
    final data = UriData.parse(element.url);
    expect(data.mimeType, 'image/svg+xml');
    expect(data.contentAsString(), svg);
  });

  testWidgets('lays out the fitted box, the element at the picture size',
      (tester) async {
    await tester.pumpWidget(_inline(_svg));

    // 120 x 60 scaled to the 600 column: 600 x 300.
    expect(tester.getSize(find.byKey(_pictureKey)), const Size(600, 300));
    expect(tester.getSize(find.byType(SvgImageElement)), const Size(600, 300));
  });

  testWidgets('sizes the element to the picture, centred in a wider box',
      (tester) async {
    await tester.pumpWidget(_inline(_tall));

    expect(tester.getSize(find.byKey(_pictureKey)), const Size(600, 400));
    expect(tester.getSize(find.byType(SvgImageElement)), const Size(120, 400));
    expect(
      tester.getCenter(find.byType(SvgImageElement)),
      tester.getCenter(find.byKey(_pictureKey)),
    );
  });

  testWidgets('replaces the element when the SVG text changes in place',
      (tester) async {
    // The browser's <img> is made when its element is first built, so new
    // text must get a new element, not an updated one.
    await tester.pumpWidget(_inline(_svg));
    final before = tester.element(find.byType(SvgImageElement));

    await tester.pumpWidget(_inline(_tall));

    final element =
        tester.widget<SvgImageElement>(find.byType(SvgImageElement));
    expect(element.url, _urlOf(_tall));
    expect(tester.element(find.byType(SvgImageElement)), isNot(same(before)));
    expect(tester.getSize(find.byKey(_pictureKey)), const Size(600, 400));
  });
}
