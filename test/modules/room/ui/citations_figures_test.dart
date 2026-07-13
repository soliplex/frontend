import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';

// 1x1 transparent PNG.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0A,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0x00,
  0x01,
  0x00,
  0x00,
  0x05,
  0x00,
  0x01,
  0x0D,
  0x0A,
  0x2D,
  0xB4,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

SourceReference _ref({
  required List<String> pictureRefs,
  required Map<String, Uint8List> pictureBytes,
}) =>
    SourceReference(
      documentId: 'doc-1',
      documentUri: 'file:///doc-1.pdf',
      content: 'cited content',
      chunkId: 'chunk-A',
      pictureRefs: pictureRefs,
      pictureBytes: pictureBytes,
    );

void main() {
  Widget host(SourceReference ref) => MaterialApp(
        home: Scaffold(
          body: CitationsSection(sourceReferences: [ref]),
        ),
      );

  testWidgets('renders a thumbnail only for refs that have bytes',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      pictureRefs: ['#/pictures/0', '#/pictures/1'],
      pictureBytes: {'#/pictures/0': _png}, // only ref 0 has bytes
    )));
    // Expand the citations section, then the citation row (title falls back
    // to the document URI's filename since documentTitle isn't set).
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets('tapping a thumbnail opens the zoomable full-size view',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      pictureRefs: ['#/pictures/0'],
      pictureBytes: {'#/pictures/0': _png},
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(InteractiveViewer), findsOneWidget);
  });

  testWidgets('renders no figure strip when no ref has bytes', (tester) async {
    await tester.pumpWidget(host(_ref(
      pictureRefs: ['#/pictures/0'],
      pictureBytes: const {},
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });
}
