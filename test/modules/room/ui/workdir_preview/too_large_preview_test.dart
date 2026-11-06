import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/too_large_preview.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('shows the too-large message, the sizes, and its Download button',
      (tester) async {
    await tester.pumpWidget(_wrap(const TooLargePreview(
      byteSize: 6 * 1024 * 1024,
      capBytes: 5 * 1024 * 1024,
      downloadButton: Text('the download button'),
    )));

    expect(find.text('File is too large to preview'), findsOneWidget);
    expect(find.text('6.0 MB — cap 5.0 MB'), findsOneWidget);
    expect(find.text('the download button'), findsOneWidget);
  });

  testWidgets('byte-size formatting pins the KB and MB thresholds',
      (tester) async {
    // _formatBytes uses >= for both KB and MB. A regression to > on
    // either boundary would round the boundary case to the smaller
    // unit (e.g. "1024 B" instead of "1 KB").
    Future<void> pumpFor(int bytes) => tester.pumpWidget(_wrap(TooLargePreview(
          byteSize: bytes,
          capBytes: 5 * 1024 * 1024,
          downloadButton: const SizedBox.shrink(),
        )));

    await pumpFor(1024);
    expect(find.textContaining('1 KB'), findsOneWidget,
        reason: '1024 bytes must round up to the KB unit, not stay as B');

    await pumpFor(1024 * 1024);
    expect(find.textContaining('1.0 MB'), findsOneWidget,
        reason: '1 MiB must round up to the MB unit, not stay as KB');
  });
}
