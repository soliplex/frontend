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
import 'package:soliplex_frontend/src/modules/room/ui/chunk_visualization_page.dart';
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

  @override
  Future<Uint8List> getRoomUploadFile(
    String roomId,
    String filename, {
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    fetched.add('$roomId/$filename');
    return _pdf;
  }

  /// Whether the server has the cited documents' files.
  var hasDocumentFiles = true;

  @override
  Future<Uint8List> getRagDocumentFile(
    String roomId,
    String documentId, {
    String? database,
    Duration? timeout,
    CancelToken? cancelToken,
  }) async {
    fetched.add('$roomId/$database/$documentId');
    if (!hasDocumentFiles) {
      throw const NotFoundException(message: 'document not a local file');
    }
    return _pdf;
  }

  /// The boxes requests made, as their chunk ids; [boxes] answers them.
  final boxesAsked = <(List<String>, List<String>)>[];
  DocumentBoxes? Function(List<String> chunkIds) boxes = _boxesFor;

  @override
  Future<DocumentBoxes> getDocumentBoxes(
    String roomId,
    String documentId, {
    required List<String> chunkIds,
    List<String> contextRefs = const [],
    String? database,
    CancelToken? cancelToken,
  }) async {
    boxesAsked.add((chunkIds, contextRefs));
    return boxes(chunkIds) ??
        (throw const ApiException(statusCode: 500, message: 'boom'));
  }

  @override
  Future<ChunkVisualization> getChunkVisualization(
    String roomId,
    String chunkId, {
    List<String>? refs,
    bool expand = false,
    String? database,
    CancelToken? cancelToken,
  }) async =>
      ChunkVisualization(
        chunkId: chunkId,
        documentUri: 'notes.pdf',
        imagesBase64: const [],
      );
}

/// One anchor box per chunk, on the page named by the chunk id's digit.
DocumentBoxes _boxesFor(List<String> chunkIds) => DocumentBoxes(
      documentId: 'doc-1',
      anchor: [
        for (final id in chunkIds)
          PassageBox(
            page: int.parse(id.substring(1)),
            left: 10,
            top: 700,
            right: 300,
            bottom: 650,
          ),
      ],
      context: const [],
    );

PdfPassage _passageOf(List<String> chunkIds) => PdfPassage(
      anchor: [
        for (final box in _boxesFor(chunkIds).anchor)
          PdfPassageBox(
            page: box.page,
            left: box.left,
            top: box.top,
            right: box.right,
            bottom: box.bottom,
          ),
      ],
    );

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

      expect(find.byTooltip('Open'), findsOneWidget,
          reason: 'only the PDF has somewhere to open');
      await tester.tap(find.text('brief.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(PdfViewerPane), findsOneWidget);
      expect(api.fetched, ['room-1/brief.pdf']);
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

  group('from a citation', () {
    SourceReference cited(String chunkId, {List<String>? chunkIds}) =>
        SourceReference(
          documentId: 'doc-1',
          documentUri: 'file:///srv/notes.pdf',
          content: 'Passage $chunkId',
          chunkId: chunkId,
          chunkIds: chunkIds ?? [chunkId],
          documentTitle: 'notes.pdf',
          docItemRefs: ['#/texts/$chunkId'],
          chunkPageNumbers: [int.parse(chunkId.substring(1))],
          database: 'notes',
        );

    void seedCitations() {
      api.nextThreadHistory = ThreadHistory(
        messages: [
          TextMessage(
            id: 'u1',
            user: ChatUser.user,
            createdAt: DateTime(2026, 3, 1),
            text: 'What do the notes say?',
          ),
          TextMessage(
            id: 'a1',
            user: ChatUser.assistant,
            createdAt: DateTime(2026, 3, 1),
            text: 'They say two things.',
          ),
        ],
        messageStates: {
          'u1': MessageState(
            userMessageId: 'u1',
            sourceReferences: [
              cited('c2'),
              cited('c4', chunkIds: ['c4', 'c5']),
            ],
          ),
        },
      );
    }

    Future<void> openFirst(WidgetTester tester) async {
      await tester.tap(find.byTooltip('View source PDF').first);
      await tester.pumpAndSettle();
    }

    testWidgets('opens the document beside the chat, marking the passage',
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      seedCitations();
      await pump(tester);

      await openFirst(tester);

      expect(find.byType(PdfViewerPane), findsOneWidget);
      expect(api.fetched, ['room-1/notes/doc-1']);
      expect(api.boxesAsked, hasLength(1));
      expect(api.boxesAsked.single.$1, ['c2']);
      expect(api.boxesAsked.single.$2, ['#/texts/c2']);
      expect(views.last.initialPage, 2);
      expect(find.text('1 / 2'), findsOneWidget);

      views.ready();
      await tester.pump();
      expect(views.document.passages, [
        _passageOf(['c2'])
      ]);
    });

    testWidgets('steps to the next citation, with every chunk it merged',
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      seedCitations();
      await pump(tester);
      await openFirst(tester);
      views.ready();
      await tester.pump();

      await tester.tap(find.byTooltip('Next citation'));
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(api.boxesAsked.last.$1, ['c4', 'c5']);
      expect(views.document.passages.last, _passageOf(['c4', 'c5']));
      expect(api.fetched, hasLength(1), reason: 'the same file');

      await tester.tap(find.byTooltip('Previous citation'));
      await tester.pumpAndSettle();
      expect(views.document.passages.last, _passageOf(['c2']));
      expect(api.boxesAsked, hasLength(2), reason: 'kept from before');
    });

    testWidgets("says which page a passage it couldn't mark is on",
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      seedCitations();
      api.boxes = (_) => null;
      await pump(tester);

      await openFirst(tester);

      expect(
        find.text("Couldn't mark the passage — it's on page 2."),
        findsOneWidget,
      );
      expect(views.last.initialPage, 2);
    });

    testWidgets("shows the rendered pages of a document with no file",
        (tester) async {
      setWindow(tester, const Size(1600, 900));
      seedCitations();
      api.hasDocumentFiles = false;
      await pump(tester);

      await openFirst(tester);

      expect(find.byType(PdfViewerPane), findsNothing);
      expect(find.byType(ChunkVisualizationPage), findsOneWidget);
    });
  });
}
