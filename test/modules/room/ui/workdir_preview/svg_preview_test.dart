import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/svg_preview.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _validSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>';

void main() {
  testWidgets('valid SVG bytes render via SvgPicture', (tester) async {
    final bytes = Uint8List.fromList(utf8.encode(_validSvg));
    await tester.pumpWidget(_wrap(SvgPreview(
      bytes: bytes,
      fallback: const Text('FALLBACK'),
    )));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('FALLBACK'), findsNothing);
  });

  testWidgets('malformed SVG bytes swap in the fallback widget',
      (tester) async {
    final garbage = Uint8List.fromList(utf8.encode('not valid <svg garbage'));
    await tester.pumpWidget(_wrap(SvgPreview(
      bytes: garbage,
      fallback: const Text('FALLBACK'),
    )));
    // First pump renders SvgPicture which then schedules a post-frame
    // callback to flip the failure state. settle drains it.
    await tester.pumpAndSettle();

    expect(find.text('FALLBACK'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });
}
