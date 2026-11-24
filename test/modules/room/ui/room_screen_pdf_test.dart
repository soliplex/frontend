import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/room/agent_runtime_manager.dart';
import 'package:soliplex_frontend/src/modules/room/file_downloads_registry.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort_preference.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pdf_quote.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/pending_quotes.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/quote_cards.dart';
import 'package:soliplex_frontend/src/modules/room/pdf/quoted_context.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chat_input.dart';
import 'package:soliplex_frontend/src/modules/room/ui/file_row_download_action.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_screen.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker_registry.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_document_view.dart';
import 'package:soliplex_frontend/src/shared/pdf/pdf_viewer_pane.dart';
import 'package:soliplex_frontend/src/stores/document_selections.dart';
import 'package:soliplex_frontend/src/stores/run_registry.dart';

import '../../../helpers/fakes.dart';
import '../../../helpers/test_server_entry.dart';
import '../../../shared/pdf/fake_pdf_document.dart';

final _pdf = Uint8List.fromList([0x25, 0x50, 0x44, 0x46]);

/// Serves one room upload's bytes, and counts the fetches.
class _PdfApi extends FakeSoliplexApi {
  final fetched = <String>[];

  /// Thrown by every room upload fetch from now on, when set.
  Object? fetchError;

  @override
  Future<Uint8List> getRoomUploadFile(
    String roomId,
    String filename, {
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    fetched.add('$roomId/$filename');
    if (fetchError case final error?) throw error;
    return _pdf;
  }
}

const _brief = RoomUploadPdf(roomId: 'room-1', filename: 'brief.pdf');
const _waiting = PdfQuote(
  text: 'The waiting passage.',
  documentTitle: 'brief.pdf',
  pageNumber: 3,
  source: _brief,
);

void main() {
  late _PdfApi api;
  late ServerEntry entry;
  late AgentRuntimeManager runtimeManager;
  late RunRegistry registry;
  late Signal<Map<String, ServerEntry>> servers;
  late UploadTrackerRegistry uploadRegistry;
  late FileDownloadsRegistry downloadRegistry;
  late PendingQuotesRegistry quotes;
  late FakePdfDocumentViews views;
  late List<String> saved;

  setUp(() {
    api = _PdfApi()
      ..nextRooms = [Room(id: 'room-1', name: 'Test Room')]
      ..nextThreads = [
        ThreadInfo(
          id: 'thread-1',
          roomId: 'room-1',
          name: 'Test thread',
          createdAt: DateTime(2026, 3, 1),
        ),
        ThreadInfo(
          id: 'thread-2',
          roomId: 'room-1',
          name: 'Other thread',
          createdAt: DateTime(2026, 3, 2),
        ),
      ]
      ..nextThreadHistory = ThreadHistory(messages: const []);
    entry = createTestServerEntry(api: api);
    runtimeManager = AgentRuntimeManager(
      platform: TestPlatformConstraints(),
      toolRegistryResolver: (_) async => const ToolRegistry(),
      logger: testLogger(),
      forwardedPropsFor: (_) => () => const {},
      servers: emptyServers(),
    );
    registry = RunRegistry(servers: emptyServers());
    servers = Signal({entry.serverId: entry});
    uploadRegistry = UploadTrackerRegistry(servers: servers);
    saved = [];
    downloadRegistry = FileDownloadsRegistry(
      servers: servers,
      saveFile: ({required String fileName, required Uint8List bytes}) async {
        saved.add(fileName);
        return '/tmp/$fileName';
      },
      isWeb: false,
    );
    quotes = PendingQuotesRegistry(servers: servers);
    views = FakePdfDocumentViews();
  });

  tearDown(() async {
    await runtimeManager.dispose();
    registry.dispose();
    uploadRegistry.dispose();
    downloadRegistry.dispose();
    quotes.dispose();
    servers.dispose();
  });

  RoomQuotes roomQuotes() => quotes.quotesFor(entry: entry, roomId: 'room-1');

  void setWindow(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  RoomScreen screen({String? threadId = 'thread-1'}) => RoomScreen(
        appName: 'Test App',
        serverEntry: entry,
        roomId: 'room-1',
        threadId: threadId,
        runtimeManager: runtimeManager,
        registry: registry,
        uploadRegistry: uploadRegistry,
        downloadRegistry: downloadRegistry,
        fileSort: FileSortPreference(),
        documentSelections: DocumentSelections(),
        pendingQuotes: quotes,
        pdfDocumentViewFactory: views.call,
      );

  Future<void> pump(WidgetTester tester,
      {String? threadId = 'thread-1'}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: screen(threadId: threadId),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the waiting quote's PDF from its chip above the composer.
  Future<void> openFromChip(WidgetTester tester) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ChatInput),
        matching: find.textContaining('The waiting passage'),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('beside the conversation', () {
    testWidgets(
        'a quote chip opens its PDF at its page, with the composer '
        'still in view', (tester) async {
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);

      await openFromChip(tester);

      expect(find.byType(PdfViewerPane), findsOneWidget);
      expect(find.byType(ChatInput), findsOneWidget);
      expect(api.fetched, ['room-1/brief.pdf']);
      expect(views.last.initialPage, 3);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('Ask about this adds a quote to the thread', (tester) async {
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);
      await openFromChip(tester);
      views.ready();
      views.document
        ..report(const PdfViewStatus(hasSelection: true))
        ..selection =
            const PdfSelectedText(text: 'A new passage.', pageNumber: 5);
      await tester.pump();

      await tester.tap(find.text('Ask about this'));
      await tester.pump();

      final waiting = roomQuotes().peek('thread-1');
      expect(waiting.map((q) => q.text),
          ['The waiting passage.', 'A new passage.']);
      expect(waiting.last.pageNumber, 5);
      expect(waiting.last.source, _brief);
      expect(find.byType(QuoteCard), findsNWidgets(2));
    });

    testWidgets('Close closes it', (tester) async {
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);
      await openFromChip(tester);

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewerPane), findsNothing);
    });

    testWidgets('typing in its search stays in its search', (tester) async {
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);
      await openFromChip(tester);
      views.ready();
      await tester.pump();

      await tester.tap(find.byTooltip('Search in document'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
      await tester.pump();

      // Type-to-focus would have moved focus to the composer.
      final focused = FocusManager.instance.primaryFocus!.context!;
      expect(
        find.ancestor(
          of: find.byWidget(focused.widget),
          matching: find.byType(PdfViewerPane),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        "leaving the thread closes a thread's file but keeps a "
        "room's", (tester) async {
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);
      await openFromChip(tester);

      await pump(tester, threadId: 'thread-2');
      expect(find.byType(PdfViewerPane), findsOneWidget,
          reason: 'a room upload belongs to every thread');
    });

    testWidgets('the divider resizes it', (tester) async {
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);
      await openFromChip(tester);
      final before = tester.getSize(find.byType(PdfViewerPane)).width;

      await tester.drag(
        find.byType(VerticalDivider).last,
        const Offset(-120, 0),
      );
      await tester.pump();
      // Less than the full 120: the drag spends its first pixels clearing
      // the gesture's slop.
      expect(
        tester.getSize(find.byType(PdfViewerPane)).width,
        greaterThan(before + 60),
        reason: 'dragging toward the chat widens the viewer',
      );
    });
  });

  group('from the files panel', () {
    testWidgets("a room upload that is a PDF opens in the viewer",
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      api
        ..nextRoom = const Room(
          id: 'room-1',
          name: 'Attachable',
          acceptsRoomUploads: true,
          acceptsThreadUploads: true,
        )
        ..nextRoomUploads = [
          FileUpload(
            filename: 'brief.pdf',
            url: Uri.parse('https://example.com/brief.pdf'),
          ),
          FileUpload(
            filename: 'notes.txt',
            url: Uri.parse('https://example.com/notes.txt'),
          ),
        ];
      await pump(tester);
      await tester.tap(find.byIcon(Icons.folder));
      await tester.pumpAndSettle();

      await tester.tap(find.text('brief.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfViewerPane), findsOneWidget);
      expect(api.fetched, ['room-1/brief.pdf']);
    });
  });

  group("the viewer's Download", () {
    Future<void> openBriefFromFiles(WidgetTester tester) async {
      setWindow(tester, const Size(1600, 900));
      api
        ..nextRoom = const Room(
          id: 'room-1',
          name: 'Attachable',
          acceptsRoomUploads: true,
          acceptsThreadUploads: true,
        )
        ..nextRoomUploads = [
          FileUpload(
            filename: 'brief.pdf',
            url: Uri.parse('https://example.com/brief.pdf'),
          ),
        ];
      await pump(tester);
      await tester.tap(find.byIcon(Icons.folder));
      await tester.pumpAndSettle();
      await tester.tap(find.text('brief.pdf'));
      await tester.pumpAndSettle();
    }

    Finder inViewer(Finder finder) =>
        find.descendant(of: find.byType(PdfViewerPane), matching: finder);
    Finder inRow(Finder finder) => find.descendant(
        of: find.byType(FileRowDownloadAction), matching: finder);

    testWidgets("is the file row's download", (tester) async {
      await openBriefFromFiles(tester);

      await tester.tap(inViewer(find.byTooltip('Download')));
      await tester.pump();
      await tester.pump();

      expect(saved, ['brief.pdf']);
      expect(inViewer(find.byTooltip('Saved')), findsOneWidget);
      expect(inRow(find.byTooltip('Saved')), findsOneWidget);

      await tester.pump(const Duration(seconds: 2));
      expect(inViewer(find.byTooltip('Download')), findsOneWidget);
      expect(inRow(find.byTooltip('Download')), findsOneWidget);
    });

    testWidgets('that fails after the viewer closed shows on its row',
        (tester) async {
      await openBriefFromFiles(tester);
      api.fetchError = const ApiException(message: 'boom', statusCode: 500);

      await tester.tap(inViewer(find.byTooltip('Download')));
      await tester.tap(inViewer(find.byTooltip('Close')));
      await tester.pumpAndSettle();

      expect(find.byType(PdfViewerPane), findsNothing);
      expect(saved, isEmpty);
      expect(
        inRow(
          find.byTooltip(
            'Download failed: Server is temporarily unavailable. '
            'Tap to retry.',
          ),
        ),
        findsOneWidget,
      );
    });
  });

  group('from a link in an answer', () {
    TextMessage answer(String text) => TextMessage(
          id: 'a1',
          user: ChatUser.assistant,
          createdAt: DateTime(2026, 3, 1),
          text: text,
        );

    testWidgets('a public .pdf link opens as itself, with no credentials',
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      api.nextThreadHistory = ThreadHistory(
        messages: [
          answer('[the paper](https://arxiv.org/pdf/2401.1.pdf)'),
        ],
      );
      await pump(tester);

      await tester.tap(find.text('the paper', findRichText: true));
      await tester.pumpAndSettle();

      expect(find.byType(PdfViewerPane), findsOneWidget);
      expect(views.last.uri, Uri.parse('https://arxiv.org/pdf/2401.1.pdf'));
      expect(api.fetched, isEmpty);
    });

    testWidgets("a link to the server's own upload opens as that upload",
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      final upload = entry.serverUrl.resolve(
        '/api/v1/uploads/room-1/file/brief.pdf',
      );
      api.nextThreadHistory = ThreadHistory(
        messages: [answer('[brief.pdf]($upload)')],
      );
      await pump(tester);

      await tester.tap(find.text('brief.pdf', findRichText: true));
      await tester.pumpAndSettle();

      expect(api.fetched, ['room-1/brief.pdf']);
      expect(views.last.bytes, isNotNull);
    });
  });

  group('over the conversation', () {
    testWidgets('on a phone it opens as a page, and Back to chat returns',
        (tester) async {
      setWindow(tester, const Size(400, 800));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);
      await openFromChip(tester);

      expect(find.byType(PdfViewerPane), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ChatInput), findsNothing, reason: 'covered');

      views.ready();
      views.document
        ..report(const PdfViewStatus(hasSelection: true))
        ..selection = const PdfSelectedText(text: 'Taken here.', pageNumber: 1);
      await tester.pump();
      await tester.tap(find.text('Ask about this'));
      await tester.pumpAndSettle();
      expect(find.text('Added to your message'), findsOneWidget);

      await tester.tap(find.text('Back to chat'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewerPane), findsNothing);
      expect(find.byType(QuoteCard), findsNWidgets(2));
    });

    testWidgets('a wide window too crowded for a pane opens a dialog',
        (tester) async {
      // The rail and the sidebar leave the content area under two panes.
      setWindow(tester, const Size(900, 800));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);
      await openFromChip(tester);

      expect(find.byType(Dialog), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewerPane), findsNothing);
    });
  });

  group('quotes in the conversation', () {
    Future<void> sendTyped(WidgetTester tester, String text) async {
      await tester.enterText(
        find.descendant(
          of: find.byType(ChatInput),
          matching: find.byType(TextField),
        ),
        text,
      );
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
    }

    testWidgets('sending puts the waiting quotes ahead of the text',
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      final stream = RecordingAgUiStreamClient();
      api.nextCreateRun = RunInfo(
        id: 'run-1',
        threadId: 'thread-1',
        createdAt: DateTime(2026, 3, 1),
      );
      entry = createTestServerEntry(api: api, agUiStreamClient: stream);
      servers.value = {entry.serverId: entry};
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);

      await sendTyped(tester, 'What does it mean?');

      expect(
        stream.inputs.single.messages!.last,
        isA<UserMessage>().having(
          (message) => (message.messageContent as TextContent).text,
          'text',
          '${formatQuotedContext([_waiting])}What does it mean?',
        ),
      );
      expect(roomQuotes().peek('thread-1'), isEmpty);
    });

    testWidgets('a failed send gives the quotes and the text back',
        (tester) async {
      // The default stream client fails every run.
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      await pump(tester);

      await sendTyped(tester, 'What does it mean?');

      expect(roomQuotes().peek('thread-1'), [_waiting]);
      final composer = tester.widget<TextField>(
        find.descendant(
          of: find.byType(ChatInput),
          matching: find.byType(TextField),
        ),
      );
      expect(composer.controller!.text, 'What does it mean?');
    });

    testWidgets("a quote card whose file can't be found says so",
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      api.nextThreadHistory = ThreadHistory(
        messages: [
          TextMessage(
            id: 'u1',
            user: ChatUser.user,
            createdAt: DateTime(2026, 3, 1),
            text: '${formatQuotedContext([
                  const PdfQuote(
                    text: 'An old passage.',
                    documentTitle: 'gone.pdf',
                    pageNumber: 2,
                  ),
                ])}Why?',
          ),
        ],
      );
      await pump(tester);

      await tester.tap(find.byType(QuoteCard));
      await tester.pump();
      expect(find.text("Can't find gone.pdf in this thread."), findsOneWidget);
      expect(find.byType(PdfViewerPane), findsNothing);
    });

    testWidgets('a quote card reopens a file opened this visit',
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      roomQuotes().add('thread-1', _waiting);
      api.nextThreadHistory = ThreadHistory(
        messages: [
          TextMessage(
            id: 'u1',
            user: ChatUser.user,
            createdAt: DateTime(2026, 3, 1),
            text: '${formatQuotedContext([
                  const PdfQuote(
                    text: 'Earlier.',
                    documentTitle: 'brief.pdf',
                    pageNumber: 7,
                  ),
                ])}Why?',
          ),
        ],
      );
      await pump(tester);
      await openFromChip(tester);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(QuoteCard),
          matching: find.text('p. 7 · brief.pdf'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PdfViewerPane), findsOneWidget);
      expect(views.last.initialPage, 7);
    });
  });
}
