import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/svg_preview.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

const _validSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"/>';

void main() {
  testWidgets('valid SVG content renders via SvgPicture', (tester) async {
    await tester.pumpWidget(_wrap(const SvgPreview(
      content: _validSvg,
      fallback: Text('FALLBACK'),
    )));
    await tester.pumpAndSettle();

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('FALLBACK'), findsNothing);
  });

  testWidgets('malformed SVG content swaps in the fallback widget',
      (tester) async {
    await tester.pumpWidget(_wrap(const SvgPreview(
      content: 'not valid <svg garbage',
      fallback: Text('FALLBACK'),
    )));
    // First pump renders SvgPicture which then schedules a post-frame
    // callback to flip the failure state. settle drains it.
    await tester.pumpAndSettle();

    expect(find.text('FALLBACK'), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsNothing);
  });

  testWidgets('failure state resets when content changes', (tester) async {
    // Pager swiping to a different SVG file reuses the same SvgPreview
    // element with new content. A regression that didn't reset
    // [_failed] on content change would leave the fallback stuck even
    // after the user navigates to a valid SVG.
    await tester.pumpWidget(_wrap(const SvgPreview(
      content: 'not valid <svg garbage',
      fallback: Text('FALLBACK'),
    )));
    await tester.pumpAndSettle();
    expect(find.text('FALLBACK'), findsOneWidget);

    await tester.pumpWidget(_wrap(const SvgPreview(
      content: _validSvg,
      fallback: Text('FALLBACK'),
    )));
    await tester.pumpAndSettle();

    expect(find.text('FALLBACK'), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);
  });
}
