import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show ApiException, NotFoundException;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_document_view.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_source.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_viewer_pane.dart';

import '../../helpers/selectable_finder.dart';
import 'fake_pdf_document.dart';

final _pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);

void main() {
  late FakePdfDocumentViews views;
  late int fetches;
  late List<(Uint8List, String)> saved;
  late List<PdfSelectedText> asked;

  setUp(() {
    views = FakePdfDocumentViews();
    fetches = 0;
    saved = [];
    asked = [];
  });

  PdfViewerSource bytesSource({
    Future<Uint8List> Function()? fetch,
    int? sizeBytes,
    String key = 'thread-upload:r/t/report.pdf',
  }) =>
      PdfViewerSource(
        title: 'report.pdf',
        origin: 'Thread upload',
        cacheKey: key,
        sizeBytes: sizeBytes,
        load: PdfLoadBytes(
          fetch ??
              () async {
                fetches++;
                return _pdf;
              },
        ),
      );

  final linkSource = PdfViewerSource(
    title: 'paper.pdf',
    origin: 'Linked from example.com',
    cacheKey: 'link:example.com/paper.pdf',
    load: PdfLoadUri(Uri.parse('https://example.com/paper.pdf')),
  );

  Future<void> pump(
    WidgetTester tester,
    PdfViewerSource source, {
    int initialPage = 1,
    PdfPassage? passage,
    Widget? banner,
    bool canAsk = true,
    bool canSave = true,
    Future<List<PdfTextBlock>> Function()? loadOcrText,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: PdfViewerPane(
              source: source,
              initialPage: initialPage,
              passage: passage,
              banner: banner,
              documentViewFactory: views.call,
              onClose: () {},
              onAskAbout: canAsk ? asked.add : null,
              onSave: canSave
                  ? (bytes, name) async => saved.add((bytes, name))
                  : null,
              loadOcrText: loadOcrText,
            ),
          ),
        ),
      );

  Future<void> openMenuItem(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  group('opening', () {
    testWidgets('fetches the bytes and hands them to the document',
        (tester) async {
      await pump(tester, bytesSource(), initialPage: 3);
      await tester.pump();

      expect(fetches, 1);
      expect(views.last.bytes, _pdf);
      expect(views.last.uri, isNull);
      expect(views.last.sourceName, 'thread-upload:r/t/report.pdf');
      expect(views.last.initialPage, 3);
    });

    testWidgets('shows that it is opening while the fetch runs',
        (tester) async {
      final pending = Completer<Uint8List>();
      await pump(tester, bytesSource(fetch: () => pending.future));

      expect(find.text('Opening report.pdf…'), findsOneWidget);
      expect(views.requests, isEmpty);

      pending.complete(_pdf);
      await tester.pump();
      expect(find.text('Opening report.pdf…'), findsNothing);
      expect(views.requests, hasLength(1));
    });

    testWidgets('loads a link without fetching anything itself',
        (tester) async {
      await pump(tester, linkSource);

      expect(views.last.uri, Uri.parse('https://example.com/paper.pdf'));
      expect(views.last.bytes, isNull);
    });

    testWidgets('shows the title, the origin and, once open, the page',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();

      expect(find.text('report.pdf'), findsOneWidget);
      expect(selectionRegionOf(find.text('report.pdf')), findsOneWidget);
      expect(find.text('Thread upload'), findsOneWidget);

      views.ready();
      await tester.pump();
      expect(find.text('Thread upload · Page 1 of 5'), findsOneWidget);

      views.document.report(const PdfViewStatus(pageNumber: 4, pageCount: 5));
      await tester.pump();
      expect(find.text('Thread upload · Page 4 of 5'), findsOneWidget);
    });
  });

  group('size cap', () {
    testWidgets('turns away a file listed as too large, without fetching it',
        (tester) async {
      await pump(tester, bytesSource(sizeBytes: pdfViewerSizeCapBytes + 1));

      expect(find.text('Too large to open here'), findsOneWidget);
      expect(fetches, 0);
      expect(views.requests, isEmpty);

      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(fetches, 1, reason: 'downloading fetches it then');
      expect(saved.single.$2, 'report.pdf');
    });

    testWidgets(
        'turns away a fetched file over the cap, and saves what it '
        'fetched', (tester) async {
      final big = Uint8List(pdfViewerSizeCapBytes + 1);
      await pump(
        tester,
        bytesSource(
          fetch: () async {
            fetches++;
            return big;
          },
        ),
      );
      await tester.pump();

      expect(find.text('Too large to open here'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(fetches, 1);
      expect(saved.single.$1, same(big));
    });
  });

  group('failures', () {
    testWidgets('a file that is gone offers no retry', (tester) async {
      await pump(
        tester,
        bytesSource(
          fetch: () async => throw const NotFoundException(message: 'gone'),
        ),
      );
      await tester.pump();

      expect(find.text('This file is no longer available'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('any other fetch failure retries', (tester) async {
      var attempts = 0;
      await pump(
        tester,
        bytesSource(
          fetch: () async {
            attempts++;
            if (attempts == 1) {
              throw const ApiException(message: 'boom', statusCode: 500);
            }
            return _pdf;
          },
        ),
      );
      await tester.pump();
      expect(find.text("Couldn't load report.pdf"), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(views.last.bytes, _pdf);
    });

    testWidgets(
        'a link that fails to load offers the browser, not a '
        'download', (tester) async {
      await pump(tester, linkSource);
      views.last.onLoadFailed(Exception('CORS'), null);
      await tester.pump();

      expect(find.text("Couldn't open this PDF here"), findsOneWidget);
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('fetched bytes that do not open can still be saved',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.last.onLoadFailed(Exception('not a PDF'), null);
      await tester.pump();

      expect(find.text("Couldn't open report.pdf"), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(fetches, 1, reason: 'the bytes already held are saved');
      expect(saved.single.$1, _pdf);
    });

    testWidgets('a failure from a superseded load is ignored', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      final stale = views.last;

      await pump(tester, bytesSource(key: 'thread-upload:r/t/other.pdf'));
      await tester.pump();
      stale.onLoadFailed(Exception('late'), null);
      await tester.pump();

      expect(find.textContaining("Couldn't"), findsNothing);
    });
  });

  group('passwords', () {
    testWidgets('asks for a password and hands it to the document',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();

      final answer = views.last.passwordProvider();
      await tester.pumpAndSettle();
      expect(find.text('Password required'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'hunter2');
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(await answer, 'hunter2');
    });

    testWidgets('says the last one was wrong when asked again', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();

      unawaited(Future.value(views.last.passwordProvider()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      unawaited(Future.value(views.last.passwordProvider()));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect password'), findsOneWidget);
    });

    testWidgets('gives up after three tries', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();

      for (var i = 0; i < 3; i++) {
        unawaited(Future.value(views.last.passwordProvider()));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
      }
      expect(await views.last.passwordProvider(), isNull);
      expect(find.text('Password required'), findsNothing);
    });

    testWidgets('a document that fails after a password prompt is protected',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();

      unawaited(Future.value(views.last.passwordProvider()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      views.last.onLoadFailed(Exception('password'), null);
      await tester.pump();

      expect(find.text('report.pdf is password-protected'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Download'), findsOneWidget);
    });
  });

  group('Ask about this', () {
    testWidgets('appears while text is selected and hands the selection on',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();
      expect(find.text('Ask about this'), findsNothing);

      views.document
        ..report(const PdfViewStatus(hasSelection: true))
        ..selection = const PdfSelectedText(text: 'cited line', pageNumber: 2);
      await tester.pump();
      await tester.tap(find.text('Ask about this'));
      await tester.pump();

      expect(asked.single.text, 'cited line');
      expect(asked.single.pageNumber, 2);
    });

    testWidgets('is offered to the document context menu', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();

      views.document.selection =
          const PdfSelectedText(text: 'from the menu', pageNumber: 1);
      views.last.onAskAbout!();
      await tester.pump();

      expect(asked.single.text, 'from the menu');
    });

    testWidgets('explains a document that forbids copying', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      views.document
        ..report(const PdfViewStatus(hasSelection: true))
        ..selection = const PdfSelectionCopyForbidden();
      await tester.pump();
      await tester.tap(find.text('Ask about this'));
      await tester.pump();

      expect(asked, isEmpty);
      expect(find.textContaining("doesn't allow copying"), findsOneWidget);
    });

    testWidgets('is not offered where there is nothing to ask', (tester) async {
      await pump(tester, bytesSource(), canAsk: false);
      await tester.pump();
      views.ready();
      views.document.report(const PdfViewStatus(hasSelection: true));
      await tester.pump();

      expect(find.text('Ask about this'), findsNothing);
      expect(views.last.onAskAbout, isNull);
    });
  });

  group('controls', () {
    testWidgets('searches as the user types and steps through matches',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();

      await tester.tap(find.byTooltip('Search in document'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'retrieval');
      expect(views.document.searches.last, 'retrieval');

      views.document.report(
        const PdfViewStatus(matchCount: 3, currentMatch: 0),
      );
      await tester.pump();
      expect(find.text('1 of 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Next match'));
      await tester.tap(find.byTooltip('Previous match'));
      expect(
        views.document.calls,
        containsAllInOrder(['nextMatch', 'previousMatch']),
      );

      await tester.tap(find.byTooltip('Close search'));
      await tester.pump();
      expect(views.document.searches.last, '', reason: 'closing clears it');
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('says when nothing matched', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();
      await tester.tap(find.byTooltip('Search in document'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'absent');
      await tester.pump();

      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('zooms from the menu', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();

      await openMenuItem(tester, 'Zoom in');
      await openMenuItem(tester, 'Zoom out');
      expect(views.document.calls, ['zoomIn', 'zoomOut']);
    });

    testWidgets('offers Download for fetched files and the browser for links',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsOneWidget);
      expect(find.text('Open in browser'), findsNothing);
      await tester.tap(find.text('Download'));
      await tester.pumpAndSettle();
      expect(saved.single.$1, _pdf);

      await pump(tester, linkSource);
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsNothing);
      expect(find.text('Open in browser'), findsOneWidget);
    });

    testWidgets('a new page for the same document moves to it', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();

      await pump(tester, bytesSource(), initialPage: 4);
      expect(views.document.calls, ['goToPage 4']);
      expect(fetches, 1, reason: 'not fetched again');
    });

    testWidgets('another document replaces this one', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();

      await pump(tester, bytesSource(key: 'room-upload:r/other.pdf'));
      await tester.pump();
      expect(fetches, 2);
      expect(views.last.sourceName, 'room-upload:r/other.pdf');
    });
  });

  group('passages', () {
    const first = PdfPassage(
      anchor: [
        PdfPassageBox(page: 2, left: 10, top: 700, right: 300, bottom: 650),
      ],
    );
    const second = PdfPassage(
      anchor: [
        PdfPassageBox(page: 3, left: 10, top: 500, right: 300, bottom: 450),
      ],
      context: [
        PdfPassageBox(page: 3, left: 10, top: 600, right: 300, bottom: 510),
      ],
    );

    testWidgets('marks the passage once the document is open', (tester) async {
      await pump(tester, bytesSource(), passage: first);
      await tester.pump();
      expect(views.document.passages, isEmpty, reason: 'not open yet');

      views.ready();
      await tester.pump();
      expect(views.document.passages, [first]);
    });

    testWidgets('another passage in the same document moves to it',
        (tester) async {
      await pump(tester, bytesSource(), passage: first);
      await tester.pump();
      views.ready();
      await tester.pump();

      await pump(tester, bytesSource(), passage: second);
      await pump(tester, bytesSource(), passage: second);
      await pump(tester, bytesSource());

      expect(views.document.passages, [first, second, null]);
      expect(fetches, 1, reason: 'not fetched again');
    });

    testWidgets('shows the banner under the header', (tester) async {
      await pump(
        tester,
        bytesSource(),
        banner: const Text('Citation 1 of 2'),
      );
      expect(find.text('Citation 1 of 2'), findsOneWidget);
    });

    test('a passage starts on its anchor, else its context', () {
      expect(first.firstPage, 2);
      expect(
        const PdfPassage(anchor: [], context: [
          PdfPassageBox(page: 5, left: 0, top: 1, right: 1, bottom: 0),
        ]).firstPage,
        5,
      );
      expect(const PdfPassage(anchor: []).firstPage, isNull);
      expect(second, isNot(first));
      expect(
        second.hashCode,
        PdfPassage(
          anchor: [...second.anchor],
          context: [...second.context],
        ).hashCode,
      );
    });
  });

  group('OCR text', () {
    const heading = PdfTextBlock(
      box: PdfPassageBox(page: 1, left: 10, top: 760, right: 200, bottom: 740),
      text: 'Chunking',
    );
    const paragraph = PdfTextBlock(
      box: PdfPassageBox(page: 1, left: 10, top: 700, right: 300, bottom: 650),
      text: 'Keep chunks large\nenough to carry their definitions.',
    );
    const scanned = PdfViewStatus(pageNumber: 1, textlessPages: {1});

    late int ocrLoads;

    setUp(() => ocrLoads = 0);

    Future<List<PdfTextBlock>> loadOcr() async {
      ocrLoads++;
      return const [heading, paragraph];
    }

    Future<void> open(
      WidgetTester tester, {
      Future<List<PdfTextBlock>> Function()? load,
      PdfViewStatus status = scanned,
      bool canAsk = true,
    }) async {
      await pump(
        tester,
        bytesSource(),
        loadOcrText: load ?? loadOcr,
        canAsk: canAsk,
      );
      await tester.pump();
      views.ready();
      views.document.report(status);
      await tester.pump();
    }

    testWidgets('is offered once a page has no text of its own',
        (tester) async {
      await pump(tester, bytesSource(), loadOcrText: loadOcr);
      await tester.pump();
      views.ready();
      await tester.pump();
      expect(find.byTooltip('Show OCR text'), findsNothing);

      views.document.report(scanned);
      await tester.pump();
      expect(find.byTooltip('Show OCR text'), findsOneWidget);
    });

    testWidgets('is not offered without OCR text', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      views.document.report(scanned);
      await tester.pump();

      expect(find.byTooltip('Show OCR text'), findsNothing);
    });

    testWidgets('shows the blocks, fetched once, and hides them',
        (tester) async {
      await open(tester);

      await tester.tap(find.byTooltip('Show OCR text'));
      await tester.pump();
      expect(views.document.textBlocks.last.blocks, [heading, paragraph]);

      await tester.tap(find.byTooltip('Hide OCR text'));
      await tester.pump();
      expect(views.document.textBlocks.last.blocks, isNull);

      await tester.tap(find.byTooltip('Show OCR text'));
      await tester.pump();
      expect(views.document.textBlocks.last.blocks, [heading, paragraph]);
      expect(ocrLoads, 1, reason: 'kept once fetched');
    });

    testWidgets('spins while fetching', (tester) async {
      final pending = Completer<List<PdfTextBlock>>();
      await open(tester, load: () => pending.future);

      await tester.tap(find.byTooltip('Show OCR text'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      pending.complete(const [heading]);
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(views.document.textBlocks.single.blocks, [heading]);
    });

    testWidgets('says so when the text cannot be fetched', (tester) async {
      await open(
        tester,
        load: () async => throw const ApiException(
          message: 'boom',
          statusCode: 500,
        ),
      );

      await tester.tap(find.byTooltip('Show OCR text'));
      await tester.pump();

      expect(find.text("Couldn't load the OCR text."), findsOneWidget);
      expect(views.document.textBlocks, isEmpty);
      expect(find.byTooltip('Show OCR text'), findsOneWidget);
    });

    testWidgets('shows the blocks again in a reopened document',
        (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Show OCR text'));
      await tester.pump();

      views.last.onReady(views.document);
      await tester.pump();

      expect(views.document.textBlocks, hasLength(2));
      expect(views.document.textBlocks.last.blocks, [heading, paragraph]);
    });

    testWidgets('another document starts with them hidden', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Show OCR text'));
      await tester.pump();

      await pump(
        tester,
        bytesSource(key: 'thread-upload:r/t/other.pdf'),
        loadOcrText: loadOcr,
      );
      await tester.pump();
      views.ready();
      await tester.pump();

      expect(find.byTooltip('Show OCR text'), findsOneWidget);
      expect(views.document.textBlocks, hasLength(1));
    });

    Future<void> tapBlock(WidgetTester tester, PdfTextBlock block) async {
      await tester.tap(find.byTooltip('Show OCR text'));
      await tester.pump();
      views.last.onTextBlockTap!(block);
      await tester.pumpAndSettle();
    }

    testWidgets('a tapped block opens its text, marked as chosen',
        (tester) async {
      await open(tester);
      await tapBlock(tester, paragraph);

      expect(find.text('OCR text, p. 1'), findsOneWidget);
      expect(find.text(paragraph.text), findsOneWidget);
      expect(views.document.textBlocks.last.selected, paragraph);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('OCR text, p. 1'), findsNothing);
      expect(views.document.textBlocks.last.selected, isNull);
    });

    testWidgets('copies the block', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await open(tester);
      await tapBlock(tester, paragraph);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copied, ['Keep chunks large enough to carry their definitions.']);
    });

    testWidgets('asks about the block', (tester) async {
      await open(tester);
      await tapBlock(tester, heading);

      await tester.tap(find.text('Ask about this'));
      await tester.pumpAndSettle();

      expect(asked.single.text, 'Chunking');
      expect(asked.single.pageNumber, 1);
      expect(find.text('OCR text, p. 1'), findsNothing);
    });

    testWidgets('asks about the part selected', (tester) async {
      await open(tester);
      await tapBlock(tester, paragraph);

      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.userUpdateTextEditingValue(
        editable.textEditingValue.copyWith(
          selection: const TextSelection(baseOffset: 5, extentOffset: 17),
        ),
        SelectionChangedCause.drag,
      );
      await tester.pump();
      expect(find.text('Copy selection'), findsOneWidget);

      await tester.tap(find.text('Ask about this'));
      await tester.pumpAndSettle();

      expect(asked.single.text, 'chunks large');
    });

    testWidgets('offers no asking where there is nothing to ask',
        (tester) async {
      await open(tester, canAsk: false);
      await tapBlock(tester, heading);

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Ask about this'), findsNothing);
    });

    test('blocks and statuses compare by value', () {
      expect(
        heading,
        PdfTextBlock(box: heading.box, text: heading.text),
      );
      expect(
        heading.hashCode,
        PdfTextBlock(box: heading.box, text: heading.text).hashCode,
      );
      expect(heading, isNot(paragraph));
      expect(scanned, const PdfViewStatus(pageNumber: 1, textlessPages: {1}));
      expect(
        scanned.hashCode,
        const PdfViewStatus(pageNumber: 1, textlessPages: {1}).hashCode,
      );
      expect(scanned, isNot(const PdfViewStatus(pageNumber: 1)));
      expect(
        const PdfViewStatus().copyWith(textlessPages: {2}).textlessPages,
        {2},
      );
    });
  });
}
