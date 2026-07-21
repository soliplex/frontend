import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/citations_section.dart';
import 'package:soliplex_frontend/src/modules/room/ui/pager_dots.dart';
import 'package:soliplex_frontend/src/shared/failed_image.dart';
import 'package:soliplex_frontend/src/shared/zoomable_image.dart';

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

SourceReference _ref({required List<Figure> figures}) => SourceReference(
      documentId: 'doc-1',
      documentUri: 'file:///doc-1.pdf',
      content: 'cited content',
      chunkId: 'chunk-A',
      figures: figures,
    );

void main() {
  Widget host(SourceReference ref) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: CitationsSection(sourceReferences: [ref]),
          ),
        ),
      );

  testWidgets('renders a thumbnail per figure', (tester) async {
    await tester.pumpWidget(host(_ref(
      figures: [Figure(ref: '#/pictures/0', bytes: _png)],
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
      figures: [Figure(ref: '#/pictures/0', bytes: _png)],
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
    // The dialog reuses the shared ZoomableImage viewer.
    expect(find.byType(ZoomableImage), findsOneWidget);
  });

  testWidgets('a multi-figure citation opens a pageable browser',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      figures: [
        Figure(ref: '#/pictures/0', bytes: _png),
        Figure(ref: '#/pictures/1', bytes: _png),
      ],
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    // Two thumbnails; tapping the first opens the browser at that figure.
    await tester.tap(find.byType(Image).first);
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    // More than one figure => page-dots navigation is shown.
    expect(find.byType(PagerDots), findsOneWidget);
  });

  testWidgets('tapping a figure opens the browser at that figure',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      figures: [
        Figure(ref: '#/pictures/0', bytes: _png, caption: 'cap-zero'),
        Figure(ref: '#/pictures/1', bytes: _png, caption: 'cap-one'),
      ],
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    // Tap the second thumbnail: the browser must open on that figure, not the
    // first — guarding that the tapped index is threaded into initialIndex.
    await tester.tap(find.byType(Image).at(1));
    await tester.pumpAndSettle();

    // The footer shows only the current page's caption.
    expect(find.text('cap-one'), findsOneWidget);
    expect(find.text('cap-zero'), findsNothing);
  });

  testWidgets('a thumbnail whose bytes fail to decode shows a fallback',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      figures: [
        Figure(
            ref: '#/pictures/0', bytes: Uint8List.fromList(const [1, 2, 3, 4])),
      ],
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    // Image decoding runs on the real event loop; let it fail, then rebuild.
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    expect(find.byType(FailedImage), findsOneWidget);
  });

  testWidgets('renders no figure strip when there are no figures',
      (tester) async {
    await tester.pumpWidget(host(_ref(figures: const [])));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    expect(find.byType(Image), findsNothing);
  });

  testWidgets('shows the caption in the full-size view when present',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      figures: [
        Figure(ref: '#/pictures/0', bytes: _png, caption: 'Figure 1: revenue'),
      ],
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.text('Figure 1: revenue'), findsOneWidget);
  });

  testWidgets('shows no caption footer when the figure has no caption',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      figures: [Figure(ref: '#/pictures/0', bytes: _png)],
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(
      find.descendant(of: find.byType(Dialog), matching: find.byType(Text)),
      findsNothing,
    );
  });

  testWidgets('a long caption collapses to a more toggle that expands',
      (tester) async {
    final long = 'Figure 1: ${'a long description ' * 20}';
    await tester.pumpWidget(host(_ref(
      figures: [Figure(ref: '#/pictures/0', bytes: _png, caption: long)],
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();
    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.text('more'), findsOneWidget);
    await tester.tap(find.text('more'));
    await tester.pumpAndSettle();
    expect(find.text('less'), findsOneWidget);
  });

  testWidgets('the thumbnail carries the caption as its semantic label',
      (tester) async {
    await tester.pumpWidget(host(_ref(
      figures: [
        Figure(ref: '#/pictures/0', bytes: _png, caption: 'Figure 1: revenue'),
      ],
    )));
    await tester.tap(find.text('1 source'));
    await tester.pump();
    await tester.tap(find.text('doc-1.pdf'));
    await tester.pump();

    expect(find.bySemanticsLabel('Figure 1: revenue'), findsWidgets);
  });
}
