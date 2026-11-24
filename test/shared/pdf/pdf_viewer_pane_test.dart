import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show ApiException, CancelledException, NotFoundException;
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/shared/download_feedback.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_document_view.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_source.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_viewer_pane.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../helpers/selectable_finder.dart';
import 'fake_pdf_document.dart';

final _pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);

void main() {
  late FakePdfDocumentViews views;
  late int fetches;
  late Signal<DownloadFeedbackState> downloadState;
  late int starts;
  late List<PdfSelectedText> asked;

  setUp(() {
    views = FakePdfDocumentViews();
    fetches = 0;
    downloadState = Signal<DownloadFeedbackState>(const DownloadIdle());
    starts = 0;
    asked = [];
  });

  PdfViewerSource bytesSource({
    Future<Uint8List> Function()? fetch,
    int? sizeBytes,
    String key = 'thread-upload:r/t/report.pdf',
    String title = 'report.pdf',
  }) =>
      PdfViewerSource(
        title: title,
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
    bool canAsk = true,
    bool canDownload = true,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: PdfViewerPane(
              source: source,
              initialPage: initialPage,
              documentViewFactory: views.call,
              onClose: () {},
              onAskAbout: canAsk ? asked.add : null,
              download: canDownload
                  ? PdfDownload(
                      state: () => downloadState.value,
                      start: () => starts++,
                    )
                  : null,
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
      expect(starts, 1);
      expect(fetches, 0, reason: 'its download fetches it, not the viewer');
    });

    testWidgets('turns away a fetched file over the cap, offering its download',
        (tester) async {
      await pump(
        tester,
        bytesSource(fetch: () async => Uint8List(pdfViewerSizeCapBytes + 1)),
      );
      await tester.pump();

      expect(find.text('Too large to open here'), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(starts, 1);
    });
  });

  group('Download', () {
    Future<void> pumpTooLarge(WidgetTester tester) =>
        pump(tester, bytesSource(sizeBytes: pdfViewerSizeCapBytes + 1));

    SoliplexButton bodyButton(WidgetTester tester, String label) =>
        tester.widget<SoliplexButton>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(SoliplexButton),
          ),
        );

    testWidgets('sits in the header, not the menu, and starts the download',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();

      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Download'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Download'));
      await tester.pump();
      expect(starts, 1);
    });

    testWidgets('shows a running download on its controls, which wait',
        (tester) async {
      await pumpTooLarge(tester);
      downloadState.value = const DownloadRunning();
      await tester.pump();

      expect(bodyButton(tester, 'Download').isLoading, isTrue);
      expect(find.byTooltip('Downloading'), findsOneWidget);
      await tester.tap(find.byTooltip('Downloading'));
      await tester.pump();
      expect(starts, 0);
    });

    testWidgets('shows a saved download in the header', (tester) async {
      await pumpTooLarge(tester);
      downloadState.value = const DownloadSaved();
      await tester.pump();

      expect(find.byTooltip('Saved'), findsOneWidget);
      await tester.tap(find.byTooltip('Saved'));
      await tester.pump();
      expect(starts, 0, reason: 'a save that shows starts no second one');
    });

    testWidgets('shows why a download failed, and retries it', (tester) async {
      await pumpTooLarge(tester);
      downloadState.value =
          const DownloadFailed('Server is temporarily unavailable');
      await tester.pump();

      expect(find.text('Server is temporarily unavailable'), findsOneWidget);
      expect(
        find.byTooltip(
          'Download failed: Server is temporarily unavailable. Tap to retry.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Retry download'));
      await tester.pump();
      expect(starts, 1);
    });

    testWidgets('is not offered where the file cannot be fetched',
        (tester) async {
      for (final error in [
        const NotFoundException(message: 'gone'),
        ArgumentError.value('a/b.pdf', 'filename'),
      ]) {
        await pump(
          tester,
          bytesSource(
            key: 'room-upload:r/${error.runtimeType}',
            fetch: () async => throw error,
          ),
        );
        await tester.pump();

        expect(find.byTooltip('Download'), findsNothing,
            reason: '${error.runtimeType}');
      }
    });

    testWidgets('is not offered without a download to start', (tester) async {
      await pump(tester, linkSource, canDownload: false);

      expect(find.byTooltip('Download'), findsNothing);
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

    testWidgets('a fetch refused for its address offers no retry',
        (tester) async {
      await pump(
        tester,
        bytesSource(
          fetch: () async => throw ArgumentError.value(
            'a/b.pdf',
            'filename',
            'must be one path segment',
          ),
        ),
      );
      await tester.pump();

      expect(find.text("Couldn't open report.pdf"), findsOneWidget);
      expect(
        find.text("Its address isn't one this app can request."),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('a range error from the fetch offers a retry', (tester) async {
      await pump(
        tester,
        bytesSource(fetch: () async => throw RangeError.range(5, 0, 3)),
      );
      await tester.pump();

      expect(find.text("Couldn't load report.pdf"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a cancelled fetch offers a retry', (tester) async {
      await pump(
        tester,
        bytesSource(
          fetch: () async =>
              throw const CancelledException(reason: 'HTTP client closed'),
        ),
      );
      await tester.pump();

      expect(find.text("Couldn't load report.pdf"), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a fetch that finishes after the file changed is dropped',
        (tester) async {
      final stale = Completer<Uint8List>();
      await pump(tester, bytesSource(fetch: () => stale.future));
      await pump(tester, bytesSource(key: 'thread-upload:r/t/other.pdf'));
      await tester.pump();

      stale.complete(Uint8List.fromList([1, 2, 3]));
      await tester.pump();

      expect(views.last.bytes, _pdf);
    });

    testWidgets('a fetch that fails after the file changed is ignored',
        (tester) async {
      final stale = Completer<Uint8List>();
      await pump(tester, bytesSource(fetch: () => stale.future));
      await pump(tester, bytesSource(key: 'thread-upload:r/t/other.pdf'));
      await tester.pump();

      stale.completeError(const ApiException(message: 'late', statusCode: 500));
      await tester.pump();

      expect(find.textContaining("Couldn't"), findsNothing);
      expect(views.last.bytes, _pdf);
    });

    testWidgets(
        'a link that fails to load offers the browser, not a '
        'download', (tester) async {
      await pump(tester, linkSource, canDownload: false);
      views.last.onLoadFailed(Exception('CORS'), null);
      await tester.pump();

      expect(find.text("Couldn't open this PDF here"), findsOneWidget);
      expect(find.text('Open in browser'), findsOneWidget);
      expect(find.text('Download'), findsNothing);
    });

    testWidgets('a file that does not open offers its download',
        (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.last.onLoadFailed(Exception('not a PDF'), null);
      await tester.pump();

      expect(find.text("Couldn't open report.pdf"), findsOneWidget);
      await tester.tap(find.text('Download'));
      await tester.pump();
      expect(starts, 1);
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

  group('logging', () {
    late MemorySink sink;

    setUp(() {
      sink = MemorySink();
      LogManager.instance.addSink(sink);
    });

    tearDown(LogManager.instance.reset);

    LogRecord recordOf(String message) =>
        sink.records.where((record) => record.message == message).single;

    testWidgets('keeps the whole of an address the client refuses',
        (tester) async {
      final refused = ArgumentError.value(
        'a/b.pdf',
        'filename',
        'must be one path segment',
      );
      await pump(
        tester,
        bytesSource(
          key: 'room-upload:r/a/b.pdf',
          fetch: () async => throw refused,
        ),
      );
      await tester.pump();

      final record = recordOf('Fetching a PDF failed');
      expect(record.error, same(refused));
      expect(
          record.attributes, containsPair('source', 'room-upload:r/a/b.pdf'));
    });

    testWidgets('keeps only the type of any other Error', (tester) async {
      await pump(
        tester,
        bytesSource(
          fetch: () async => throw StateError('text its thrower wrote'),
        ),
      );
      await tester.pump();

      final record = recordOf('Fetching a PDF failed');
      expect(record.error, isNull);
      expect(record.stackTrace, isNotNull);
      expect(record.attributes, containsPair('failure', 'StateError'));
      expect(
        '${record.message} ${record.attributes}',
        isNot(contains('text its thrower wrote')),
      );
    });

    testWidgets('keeps the whole of an API exception from a fetch',
        (tester) async {
      const error = ApiException(message: 'boom', statusCode: 500);
      await pump(tester, bytesSource(fetch: () async => throw error));
      await tester.pump();

      final record = recordOf('Fetching a PDF failed');
      expect(record.error, same(error));
      expect(
        record.attributes,
        containsPair('source', 'thread-upload:r/t/report.pdf'),
      );
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

    testWidgets('offers the browser for links only', (tester) async {
      await pump(tester, bytesSource());
      await tester.pump();
      views.ready();
      await tester.pump();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Open in browser'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await pump(tester, linkSource, canDownload: false);
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
}
