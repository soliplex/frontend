import 'dart:async';

import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/network_inspector.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/diagnostics_screen.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/pane_layout.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/requests_pane.dart';

import '../../../helpers/http_event_factories.dart';

/// Stands in for the platform save dialog. `saveFile` has three outcomes the
/// export branches on: a path (saved), null (a dismissed dialog — but also a
/// failed portal on Linux and any CommDlgExtendedError on Windows), and a
/// throw.
class _FakeSavePicker extends FilePickerPlatform {
  _FakeSavePicker.returns(this._path) : _thrown = null;
  _FakeSavePicker.throwing(Object this._thrown) : _path = null;

  final String? _path;
  final Object? _thrown;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    if (_thrown != null) throw _thrown;
    return _path;
  }
}

/// A save dialog that does not answer, standing in for the Android result
/// codes the plugin never resolves.
class _HangingSavePicker extends FilePickerPlatform {
  _HangingSavePicker(this._never);

  final Future<String?> _never;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) =>
      _never;
}

void main() {
  group('DiagnosticsScreen', () {
    late NetworkInspector inspector;

    setUp(() {
      inspector = NetworkInspector();
    });

    tearDown(() {
      inspector.dispose();
    });

    testWidgets('shows empty state when inspector has no events',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector)),
      );
      expect(find.text('No HTTP requests yet'), findsOneWidget);
    });

    testWidgets('shows the branded bar (no about button) and back affordance',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(appName: 'Acme', inspector: inspector),
        ),
      );

      // Branded app name in the bar; the about/versions button is dropped.
      expect(find.text('Acme'), findsOneWidget);
      expect(find.byTooltip('Diagnostics & versions'), findsNothing);
      expect(find.byTooltip('Back'), findsOneWidget);
      // The request-count heading stays hidden while the list is empty so it
      // doesn't compete with the empty state.
      expect(find.text('Requests (0)'), findsNothing);
    });

    testWidgets('surfaces the request-count heading in the body when non-empty',
        (tester) async {
      inspector.onRequest(createRequestEvent(requestId: 'req-1'));
      inspector.onResponse(createResponseEvent(requestId: 'req-1'));

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(appName: 'Acme', inspector: inspector),
        ),
      );

      expect(find.text('Requests (1)'), findsOneWidget);
    });

    testWidgets('shows event tiles when events exist', (tester) async {
      inspector.onRequest(
        createRequestEvent(
          requestId: 'req-1',
          method: 'GET',
          uri: Uri.parse('http://localhost/api/v1/rooms'),
        ),
      );
      inspector.onResponse(createResponseEvent(requestId: 'req-1'));

      // Use a narrow viewport so the list layout (not master-detail) is used
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
            home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector)),
      );
      expect(find.text('GET'), findsOneWidget);
    });

    testWidgets('tapping a row expands its detail sections inline',
        (tester) async {
      inspector.onRequest(
        createRequestEvent(
          requestId: 'req-1',
          method: 'GET',
          uri: Uri.parse('http://localhost/api/v1/rooms'),
        ),
      );
      inspector.onResponse(createResponseEvent(requestId: 'req-1'));

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector),
        ),
      );

      // Collapsed: no detail sections yet.
      expect(find.text('Summary'), findsNothing);

      await tester.tap(find.text('GET'));
      await tester.pumpAndSettle();

      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
    });

    testWidgets('clear button is disabled when no events', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector)),
      );
      final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
      expect(button.onPressed, isNull);
    });

    testWidgets('clear button is enabled when events exist', (tester) async {
      inspector.onRequest(createRequestEvent());
      await tester.pumpWidget(
        MaterialApp(
            home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector)),
      );
      final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('clear button clears events and shows empty state',
        (tester) async {
      inspector.onRequest(createRequestEvent());

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
            home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector)),
      );

      await tester
          .tap(find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
      await tester.pump();

      expect(find.text('No HTTP requests yet'), findsOneWidget);
    });

    testWidgets('clear button is enabled when only concurrency events exist',
        (tester) async {
      inspector.onConcurrencyWait(createConcurrencyWaitEvent());

      await tester.pumpWidget(
        MaterialApp(
            home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector)),
      );

      final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
      expect(
        button.onPressed,
        isNotNull,
        reason: 'Trash-can must activate when concurrency events exist '
            'even if HTTP events list is empty',
      );
    });

    testWidgets(
        'clear button clears concurrency events and hides the summary panel',
        (tester) async {
      inspector
        ..onConcurrencyWait(createConcurrencyWaitEvent(acquisitionId: 'acq-1'))
        ..onConcurrencyWait(
          createConcurrencyWaitEvent(
            acquisitionId: 'acq-2',
            waitDuration: const Duration(milliseconds: 120),
            queueDepthAtEnqueue: 2,
          ),
        );

      await tester.pumpWidget(
        MaterialApp(
            home: DiagnosticsScreen(appName: 'Soliplex', inspector: inspector)),
      );

      // Panel is visible when concurrency events exist.
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);

      await tester
          .tap(find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
      await tester.pump();

      // Panel hides itself when the list is empty.
      expect(find.byIcon(Icons.hourglass_empty), findsNothing);
      expect(inspector.concurrencyEvents, isEmpty);
    });

    // --- Filtering (the deferred toolbar, folded in) ---

    void seedRoomsAndThreads() {
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            method: 'GET',
            uri: Uri.parse('http://localhost/api/v1/rooms')))
        ..onResponse(createResponseEvent(requestId: 'req-1', statusCode: 200))
        ..onRequest(createRequestEvent(
            requestId: 'req-2',
            method: 'POST',
            uri: Uri.parse('http://localhost/api/v1/threads')))
        ..onResponse(createResponseEvent(requestId: 'req-2', statusCode: 200));
    }

    // Wide viewport → tabular tiles, which render the endpoint path as a
    // discrete Text the filters can be asserted against.
    Future<void> pumpWide(WidgetTester tester, {String? initialRunId}) async {
      tester.view.physicalSize = const Size(900, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            appName: 'Soliplex',
            inspector: inspector,
            initialRunId: initialRunId,
          ),
        ),
      );
    }

    testWidgets('search narrows the list to matching paths', (tester) async {
      seedRoomsAndThreads();
      await pumpWide(tester);
      expect(find.text('/api/v1/rooms'), findsOneWidget);
      expect(find.text('/api/v1/threads'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'threads');
      await tester.pump();

      expect(find.text('/api/v1/threads'), findsOneWidget);
      expect(find.text('/api/v1/rooms'), findsNothing);
      expect(find.text('Requests (1 / 2)'), findsOneWidget);
    });

    testWidgets('the Errors status filter hides successful exchanges',
        (tester) async {
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            method: 'GET',
            uri: Uri.parse('http://localhost/api/v1/rooms')))
        ..onResponse(createResponseEvent(requestId: 'req-1', statusCode: 200))
        ..onRequest(createRequestEvent(
            requestId: 'req-2',
            method: 'POST',
            uri: Uri.parse('http://localhost/api/v1/threads')))
        ..onResponse(createResponseEvent(requestId: 'req-2', statusCode: 500));
      await pumpWide(tester);

      await tester.tap(find.text('Errors'));
      await tester.pumpAndSettle();

      expect(find.text('/api/v1/threads'), findsOneWidget); // 500 → error
      expect(find.text('/api/v1/rooms'), findsNothing); // 200 → hidden
      // A bucket counts as a filter, or the heading reads as the whole
      // capture while the list shows a fraction of it.
      expect(find.text('Requests (1 / 2)'), findsOneWidget);
    });

    testWidgets('initialRunId scopes the list and shows a removable run chip',
        (tester) async {
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            method: 'POST',
            uri: Uri.parse('http://localhost/api/v1/threads/t1/runs/run-xyz')))
        ..onResponse(createResponseEvent(requestId: 'req-1', statusCode: 200))
        ..onRequest(createRequestEvent(
            requestId: 'req-2',
            method: 'GET',
            uri: Uri.parse('http://localhost/api/v1/rooms')))
        ..onResponse(createResponseEvent(requestId: 'req-2', statusCode: 200));
      await pumpWide(tester, initialRunId: 'run-xyz');

      expect(find.text('Run · run-xyz'), findsOneWidget);
      expect(find.text('/api/v1/threads/t1/runs/run-xyz'), findsOneWidget);
      expect(find.text('/api/v1/rooms'), findsNothing);

      // Removing the run filter restores the full list.
      await tester.tap(find.byTooltip('Clear run filter'));
      await tester.pumpAndSettle();
      expect(find.text('/api/v1/rooms'), findsOneWidget);
    });

    testWidgets('shows the no-match state and clears filters', (tester) async {
      seedRoomsAndThreads();
      await pumpWide(tester);

      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.pump();
      expect(find.text('No requests match these filters'), findsOneWidget);

      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.text('/api/v1/rooms'), findsOneWidget);
      expect(find.text('/api/v1/threads'), findsOneWidget);
    });

    testWidgets('Clear filters drops the run scope too, not just the search',
        (tester) async {
      // The run filter is the one filter the pane does not own, so clearing it
      // goes through a callback to the screen. Without that call the button
      // reports the filters cleared while the list stays scoped.
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            uri: Uri.parse('http://localhost/api/v1/rooms/r1/agui/t1/run-1')))
        ..onResponse(createResponseEvent(requestId: 'req-1'))
        ..onRequest(createRequestEvent(
            requestId: 'req-2', uri: Uri.parse('http://localhost/api/other')))
        ..onResponse(createResponseEvent(requestId: 'req-2'));
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            appName: 'Acme',
            inspector: inspector,
            initialRunId: 'run-1',
          ),
        ),
      );

      // Scoped to the run, then narrowed to nothing so the empty state's
      // "Clear filters" is the only way out.
      await tester.enterText(find.byType(TextField), 'nomatch');
      await tester.pumpAndSettle();
      expect(find.text('No requests match these filters'), findsOneWidget);

      // Named for what it takes: the scope goes with the filters, and the
      // deep link that set it cannot be re-followed from here.
      await tester.tap(find.text('Clear filters and run'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Run · '), findsNothing);
      expect(find.text('/api/other'), findsOneWidget);
    });

    testWidgets('the category filter narrows to LLM (AG-UI) traffic',
        (tester) async {
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            method: 'POST',
            uri: Uri.parse('http://localhost/api/v1/rooms/r1/agui/t1/run-1')))
        ..onResponse(createResponseEvent(requestId: 'req-1', statusCode: 200))
        ..onRequest(createRequestEvent(
            requestId: 'req-2',
            method: 'GET',
            uri: Uri.parse('http://localhost/api/v1/rooms')))
        ..onResponse(createResponseEvent(requestId: 'req-2', statusCode: 200));
      await pumpWide(tester);

      await tester.tap(find.text('LLM'));
      await tester.pumpAndSettle();

      expect(find.text('/api/v1/rooms/r1/agui/t1/run-1'), findsOneWidget);
      expect(find.text('/api/v1/rooms'), findsNothing);
      expect(find.text('Requests (1 / 2)'), findsOneWidget);
    });
  });

  group('DiagnosticsScreen log capture', () {
    late NetworkInspector inspector;
    late MemorySink sink;

    setUp(() {
      inspector = NetworkInspector();
      sink = MemorySink();
      LogManager.instance.addSink(sink);
    });

    tearDown(() {
      inspector.dispose();
      LogManager.instance.reset();
    });

    Future<void> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(appName: 'Acme', inspector: inspector),
        ),
      );
    }

    testWidgets('the Logs segment shows captured records and their count',
        (tester) async {
      LogManager.instance.getLogger('soliplex.probe').warning('probe failed');
      await pumpScreen(tester);

      // The request list is the landing pane, so the record is not on screen
      // until the segment is chosen.
      expect(find.textContaining('probe failed'), findsNothing);

      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('probe failed'), findsOneWidget);
      expect(find.text('Log records (1)'), findsOneWidget);
    });

    testWidgets('a record arriving while the Logs pane is up is rendered',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      expect(find.text('No log records captured.'), findsOneWidget);
      // Counting nothing competes with the message that says why.
      expect(find.textContaining('Log records ('), findsNothing);

      LogManager.instance.getLogger('soliplex.probe').warning('arrived late');
      await tester.pumpAndSettle();

      expect(find.textContaining('arrived late'), findsOneWidget);
    });

    testWidgets('clear empties the capture the visible pane is showing',
        (tester) async {
      inspector.onRequest(createRequestEvent(requestId: 'req-1'));
      inspector.onResponse(createResponseEvent(requestId: 'req-1'));
      LogManager.instance.getLogger('soliplex.probe').warning('kept');
      await pumpScreen(tester);

      // Logs first, deliberately: clearing requests first would let a
      // logs-pane trash-can wired to the inspector pass this test, and losing
      // the HTTP capture is the loss that matters.
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Clear all log records'));
      await tester.pumpAndSettle();
      expect(find.text('No log records captured.'), findsOneWidget);

      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.text('/api/v1/rooms'), findsOneWidget);

      await tester.tap(find.byTooltip('Clear all requests'));
      await tester.pumpAndSettle();
      expect(find.text('No HTTP requests yet'), findsOneWidget);
    });

    testWidgets('the report can be saved when only log records were captured',
        (tester) async {
      await pumpScreen(tester);

      // Nothing captured at all: there is no report worth writing.
      final action = find.widgetWithIcon(IconButton, Icons.save_alt);
      expect(tester.widget<IconButton>(action).onPressed, isNull);

      // A record with no HTTP exchange is the case the probe hits when it
      // rejects an address before any request is made. The action lives in the
      // header, above both panes, so it has to notice from either one.
      LogManager.instance
          .getLogger('soliplex.probe')
          .warning('no request made');
      await tester.pumpAndSettle();

      expect(tester.widget<IconButton>(action).onPressed, isNotNull);
    });
  });

  group('DiagnosticsScreen export outcomes', () {
    late NetworkInspector inspector;
    late MemorySink sink;
    late FilePickerPlatform originalPicker;
    setUp(() {
      inspector = NetworkInspector();
      sink = MemorySink();
      LogManager.instance.addSink(sink);
      originalPicker = FilePickerPlatform.instance;
    });

    tearDown(() {
      FilePickerPlatform.instance = originalPicker;
      // Reset regardless: a throw from dispose would otherwise leak the sink
      // into every later test.
      try {
        inspector.dispose();
      } finally {
        LogManager.instance.reset();
      }
    });

    Future<void> pumpAndSave(WidgetTester tester) async {
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      LogManager.instance.getLogger('soliplex.probe').warning('something');
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(appName: 'Acme', inspector: inspector),
        ),
      );
      await tester.tap(find.widgetWithIcon(IconButton, Icons.save_alt));
      await tester.pumpAndSettle();
    }

    testWidgets('a dismissed dialog says nothing on screen', (tester) async {
      // A cancel is the user's decision; the screen stays quiet about it.
      FilePickerPlatform.instance = _FakeSavePicker.returns(null);
      await pumpAndSave(tester);

      expect(find.textContaining('Could not finish saving'), findsNothing);
      // Recorded even so: Linux and Windows return null for real failures too,
      // and this is the only trace either leaves.
      expect(
        sink.records.map((r) => r.message),
        contains('The save dialog returned no path; the report was not '
            'written'),
      );
    });

    testWidgets('a saved file reports success', (tester) async {
      FilePickerPlatform.instance =
          _FakeSavePicker.returns('/tmp/diagnostics.txt');
      await pumpAndSave(tester);

      expect(find.byTooltip('Report saved'), findsOneWidget);
      expect(find.textContaining('Could not finish saving'), findsNothing);
    });

    testWidgets('a failing picker names the file that may be incomplete',
        (tester) async {
      // A desktop save writes after the dialog closes, so the user needs to
      // know which file to go and distrust.
      FilePickerPlatform.instance =
          _FakeSavePicker.throwing(ArgumentError('no plugin'));
      await pumpAndSave(tester);

      expect(find.textContaining('Could not finish saving'), findsOneWidget);
      expect(find.textContaining('diagnostics_'), findsOneWidget);
    });

    testWidgets('the notice outlives the glyph, which reverts', (tester) async {
      // The glyph is a two-second flash; the notice is the only lasting
      // account of a failure, and it names the file that may be truncated.
      FilePickerPlatform.instance =
          _FakeSavePicker.throwing(ArgumentError('no plugin'));
      await pumpAndSave(tester);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(find.textContaining('Could not finish saving'), findsOneWidget);
      expect(find.byTooltip('Report saved'), findsNothing);
    });
  });

  group('DiagnosticsScreen filters across panes', () {
    late NetworkInspector inspector;

    setUp(() => inspector = NetworkInspector());
    tearDown(() => inspector.dispose());

    testWidgets('a dismissed run filter stays dismissed across a pane switch',
        (tester) async {
      // The whole reason the run filter lives on the screen: the pane is
      // disposed on a switch, and re-seeding from the deep link would silently
      // re-hide traffic the user had chosen to see.
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            uri: Uri.parse('http://localhost/api/v1/rooms/r1/agui/t1/run-1')))
        ..onResponse(createResponseEvent(requestId: 'req-1'))
        ..onRequest(createRequestEvent(
            requestId: 'req-2', uri: Uri.parse('http://localhost/api/other')))
        ..onResponse(createResponseEvent(requestId: 'req-2'));

      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(
            appName: 'Acme',
            inspector: inspector,
            initialRunId: 'run-1',
          ),
        ),
      );

      expect(find.text('/api/other'), findsNothing);

      await tester.tap(find.byTooltip('Clear run filter'));
      await tester.pumpAndSettle();
      expect(find.text('/api/other'), findsOneWidget);

      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();

      expect(find.text('/api/other'), findsOneWidget);
      expect(find.textContaining('Run · '), findsNothing);
    });
  });

  group('DiagnosticsScreen save that never answers', () {
    late NetworkInspector inspector;
    late FilePickerPlatform originalPicker;

    setUp(() {
      inspector = NetworkInspector();
      originalPicker = FilePickerPlatform.instance;
    });

    tearDown(() {
      FilePickerPlatform.instance = originalPicker;
      inspector.dispose();
    });

    testWidgets('gives up and says so, without claiming the save failed',
        (tester) async {
      // A dialog that has not answered is still open and still the user's to
      // finish, so the report must not say a file may have been left behind.
      final never = Completer<String?>();
      addTearDown(() => never.complete(null));
      FilePickerPlatform.instance = _HangingSavePicker(never.future);

      inspector.onRequest(createRequestEvent(requestId: 'req-1'));
      inspector.onResponse(createResponseEvent(requestId: 'req-1'));
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(appName: 'Acme', inspector: inspector),
        ),
      );

      await tester.tap(find.widgetWithIcon(IconButton, Icons.save_alt));
      await tester.pump();
      // The action stops claiming to be available while it waits.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.save_alt),
            )
            .onPressed,
        isNull,
      );

      await tester.pump(const Duration(minutes: 6));
      await tester.pumpAndSettle();

      // Not the "a partly-written file may exist" wording: the dialog never
      // wrote anything, and the user can still complete it.
      expect(find.textContaining('Could not finish saving'), findsNothing);
      expect(find.textContaining('did not answer'), findsOneWidget);
      expect(find.textContaining('the file will still be written'),
          findsOneWidget);
      // And the action is offered again, rather than staying dead.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.save_alt),
            )
            .onPressed,
        isNotNull,
      );
    });
  });

  group('DiagnosticsScreen with no log capture installed', () {
    late NetworkInspector inspector;

    setUp(() {
      inspector = NetworkInspector();
      // Deliberately no MemorySink: the state a host app lands in when it
      // configures its own sinks.
      LogManager.instance.reset();
    });
    tearDown(() => inspector.dispose());

    testWidgets('the message is laid out in full, however short the pane',
        (tester) async {
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // One width throughout, so the line count is fixed and only the room
      // for it changes.
      Future<void> pumpTall(double height) async {
        tester.view.physicalSize = Size(390, height);
        await tester.pumpWidget(
          MaterialApp(
            home: DiagnosticsScreen(appName: 'Acme', inspector: inspector),
          ),
        );
        await tester.pumpAndSettle();
      }

      final message = find.textContaining('No log sink is installed');
      await pumpTall(844);
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      final roomy = tester.getSize(message);

      // Squeezed into a box shorter than itself, a paragraph reports the
      // box's height and clips the rest — silently losing the half of this
      // message that says what its absence does not mean. Laid out in full
      // and scrolled, its height does not depend on the viewport.
      await pumpTall(280);
      expect(tester.getSize(message), roomy);
    });

    testWidgets('says nothing is being collected, not that nothing happened',
        (tester) async {
      // Reporting an empty capture here would tell the reader the code logged
      // nothing, which is the opposite of what is true.
      tester.view.physicalSize = const Size(900, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          home: DiagnosticsScreen(appName: 'Acme', inspector: inspector),
        ),
      );

      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();

      expect(find.textContaining('No log sink is installed'), findsOneWidget);
      expect(find.text('No log records captured.'), findsNothing);
      // An absent sink is not a reason to strand the reader here: the
      // switcher sits above every state this pane can be in.
      expect(find.text('Requests'), findsOneWidget);
      // And the clear action does not offer to empty a capture that is absent.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined),
            )
            .onPressed,
        isNull,
      );
    });
  });

  group('DiagnosticsScreen controls', () {
    late NetworkInspector inspector;

    setUp(() {
      inspector = NetworkInspector();
    });

    tearDown(() {
      inspector.dispose();
    });

    void seedRoomsAndThreads() {
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            method: 'GET',
            uri: Uri.parse('http://localhost/api/v1/rooms')))
        ..onResponse(createResponseEvent(requestId: 'req-1'))
        ..onRequest(createRequestEvent(
            requestId: 'req-2',
            method: 'POST',
            uri: Uri.parse('http://localhost/api/v1/threads')))
        ..onResponse(createResponseEvent(requestId: 'req-2'));
    }

    // The app's own theme, not Material's defaults: the toggles are measured
    // here, and a density set in the shared theme would be invisible to a
    // bare MaterialApp.
    final theme =
        lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light);

    Future<void> pumpAt(
      WidgetTester tester,
      double width, {
      double height = 900,
      String? initialRunId,
    }) async {
      tester.view.physicalSize = Size(width, height);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: DiagnosticsScreen(
            appName: 'Acme',
            inspector: inspector,
            initialRunId: initialRunId,
          ),
        ),
      );
    }

    // Either side of SoliplexBreakpoints.tablet (600).
    const phone = 400.0;
    const tablet = 700.0;

    testWidgets(
        'collapsing the filters leaves the switcher and count on screen',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, tablet);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Success'), findsOneWidget);

      await tester.tap(find.text('Hide filters'));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
      expect(find.text('Success'), findsNothing);
      expect(find.text('LLM'), findsNothing);
      // The control says which state it is in, so it does not have to be
      // tapped to find out.
      expect(find.text('Show filters'), findsOneWidget);
      // Neither the switcher nor the count is part of what collapses: the
      // first would strand a user who collapsed the chrome while the Logs
      // pane was up, and the second is what says rows are being withheld.
      expect(find.text('Logs'), findsOneWidget);
      expect(find.text('Requests (2)'), findsOneWidget);
    });

    testWidgets('a filter that hides rows keeps saying so once collapsed',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, tablet);
      await tester.enterText(find.byType(TextField), 'threads');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Hide filters'));
      await tester.pumpAndSettle();

      // The count is the only thing left saying rows are being withheld.
      expect(find.text('Requests (1 / 2)'), findsOneWidget);
      expect(find.text('/api/v1/rooms'), findsNothing);

      await tester.tap(find.text('Show filters'));
      await tester.pumpAndSettle();

      // And collapsing is not a quiet reset: the query comes back with it.
      expect(find.text('threads'), findsOneWidget);
    });

    testWidgets('a resize decides for a user who has not answered',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, phone);
      // The chrome costs enough of a phone screen that the list loses to
      // it, and the list is what the reader came for.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Show filters'), findsOneWidget);

      await pumpAt(tester, tablet);

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Hide filters'), findsOneWidget);
    });

    testWidgets('a phone in landscape is wide but short, and stays collapsed',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, 844, height: 390);

      // Width alone would call this a tablet and open the filters, which in
      // 390 of height would leave almost nothing for the list.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Show filters'), findsOneWidget);
    });

    // Without the cap the control block is a fixed-height child and blows
    // through a viewport too short for it. A test fails on an overflow, so
    // reaching this state is most of the assertion.
    //
    // Not covered here: at large Dynamic Type HomeShellHeader overflows on
    // its own account, which no assertion in this file can see past.
    testWidgets('the filters yield rather than overflow a short viewport',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, 844, height: 330);

      await tester.tap(find.text('Show filters'));
      await tester.pumpAndSettle();

      // And the list keeps exactly the floor it is promised — `greaterThan(0)`
      // would pass on a one-pixel stub.
      expect(find.byType(ListView), findsOneWidget);
      expect(tester.getSize(find.byType(ListView)).height,
          PaneLayout.minListExtent);

      // The placeholder that replaces the list has the same problem and the
      // same answer: it is taller than what is left for it here, and the way
      // out of the filter has to stay reachable.
      await tester.enterText(find.byType(TextField), 'zzz-no-match');
      await tester.pumpAndSettle();

      expect(find.text('No requests match these filters'), findsOneWidget);
      // Scrolled to, not merely attached: a clip would leave the finder
      // happy and the button forever out of reach.
      await tester.ensureVisible(find.text('Clear filters'));
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      expect(find.byType(ListView), findsOneWidget);
    });

    testWidgets('the collapse control sits flush with the controls it opens',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, tablet);

      // Its right edge matches the full-width switcher's, so the heading
      // and the control read as the two ends of one row rather than as two
      // things adrift in the middle of it.
      final control = find.widgetWithText(SoliplexButton, 'Hide filters');
      final switcher = find.ancestor(
        of: find.text('Logs'),
        matching: find.bySubtype<SegmentedButton>(),
      );
      expect(
        tester.getBottomRight(control).dx,
        tester.getBottomRight(switcher).dx,
      );
    });

    testWidgets('a resize does not re-decide for a user who has answered',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, tablet);
      await tester.tap(find.text('Hide filters'));
      await tester.pumpAndSettle();

      await pumpAt(tester, phone);
      await pumpAt(tester, tablet);

      // Tablet width would open them, and did before the tap. Re-deciding on
      // every build would quietly undo it.
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('a phone remembers the filters being asked for',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, phone);

      await tester.tap(find.text('Show filters'));
      await tester.pumpAndSettle();

      // After the user answers, a pane switch must not re-decide for them.
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Requests'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('a run-scoped list says so with the filters collapsed',
        (tester) async {
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            uri: Uri.parse('http://localhost/api/v1/rooms/r1/agui/t1/run-1')))
        ..onResponse(createResponseEvent(requestId: 'req-1'))
        ..onRequest(createRequestEvent(
            requestId: 'req-2', uri: Uri.parse('http://localhost/api/other')))
        ..onResponse(createResponseEvent(requestId: 'req-2'));
      await pumpAt(tester, phone, initialRunId: 'run-1');

      // The deep link lands on a phone, where the filters start collapsed.
      expect(find.byType(TextField), findsNothing);
      // The scope is not a filter control: it withholds rows, so it names
      // itself and stays dismissable rather than hiding with the toggles.
      expect(find.text('Run · run-1'), findsOneWidget);
      expect(find.byTooltip('Clear run filter'), findsOneWidget);
    });

    testWidgets('clearing the capture leaves the run scope visible and named',
        (tester) async {
      inspector
        ..onRequest(createRequestEvent(
            requestId: 'req-1',
            uri: Uri.parse('http://localhost/api/v1/rooms/r1/agui/t1/run-1')))
        ..onResponse(createResponseEvent(requestId: 'req-1'));
      await pumpAt(tester, tablet, initialRunId: 'run-1');

      await tester.tap(find.byTooltip('Clear all requests'));
      await tester.pumpAndSettle();

      // Clearing empties the capture but not the scope, so traffic from
      // anything else still will not appear. Saying it will, with nothing on
      // screen naming the scope or offering to drop it, is a lie the user
      // cannot see through.
      expect(find.text('Run · run-1'), findsOneWidget);
      expect(find.byTooltip('Clear run filter'), findsOneWidget);
      expect(find.text('Only requests matching your filters will appear here'),
          findsOneWidget);
      expect(
        find.text('Requests will appear here as you use the app'),
        findsNothing,
      );

      await tester.tap(find.byTooltip('Clear run filter'));
      await tester.pumpAndSettle();

      expect(find.text('Requests will appear here as you use the app'),
          findsOneWidget);
    });

    testWidgets('a filter outlives the capture it was narrowing',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, tablet);
      await tester.enterText(find.byType(TextField), 'threads');
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Clear all requests'));
      await tester.pumpAndSettle();

      // Clearing the list does not clear the query, so whatever arrives
      // next is still hidden. Hiding the field that holds it would leave the
      // reader watching an empty pane for no stated reason.
      expect(find.text('threads'), findsOneWidget);
    });

    testWidgets('an empty capture offers no filter affordance', (tester) async {
      await pumpAt(tester, tablet);

      expect(find.text('Hide filters'), findsNothing);
      // Nor the filters themselves: the control that puts them away lives in
      // the heading, which an empty, unfiltered capture does not render.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Logs'), findsOneWidget);
    });

    testWidgets('the controls keep to the left margin on a wide window',
        (tester) async {
      seedRoomsAndThreads();
      await pumpAt(tester, 1400);

      // Capping their width must not centre them: the list they sit above is
      // full-bleed, so centred controls read as belonging to nothing.
      final switcher = find.ancestor(
        of: find.text('Logs'),
        matching: find.bySubtype<SegmentedButton>(),
      );
      expect(tester.getTopLeft(switcher).dx, SoliplexSpacing.s4);
      expect(
          tester.getTopLeft(find.text('Requests (2)')).dx, SoliplexSpacing.s4);
    });

    testWidgets('the switcher and the filter toggles are one size',
        (tester) async {
      seedRoomsAndThreads();
      // Wider than the control column's cap, so the toggles are measured at
      // the width they hold on any larger screen — and wide enough that no
      // segment label wraps under the test font, which would make the heights
      // differ for a reason no real font reproduces.
      await pumpAt(tester, tablet);

      // Named by a label unique to each: 'All' is a segment of both filters.
      Finder toggleWith(String label) => find.ancestor(
            of: find.text(label),
            matching: find.bySubtype<SegmentedButton>(),
          );
      final switcher = tester.getSize(toggleWith('Logs'));
      final status = tester.getSize(toggleWith('Success'));

      expect(switcher, status);

      // And the same control keeps that size on the other pane, which is the
      // whole reason both of them lay out through PaneLayout.
      await tester.tap(find.text('Logs'));
      await tester.pumpAndSettle();
      expect(tester.getSize(toggleWith('Requests')), switcher);
      expect(tester.getTopLeft(toggleWith('Requests')).dx, SoliplexSpacing.s4);
      expect(switcher.width, SoliplexBreakpoints.tablet);
      // Stacked toggles, so a mis-tap that falls short lands on the
      // neighbouring filter rather than on nothing. The group pumps the real
      // theme, so a density set there is caught as well as one set here.
      expect(switcher.height, kMinInteractiveDimension);
    });
  });

  group('RequestsPane heading', () {
    testWidgets('the heading and its control share a row that cannot overflow',
        (tester) async {
      final inspector = NetworkInspector();
      addTearDown(inspector.dispose);
      for (var n = 0; n < 12; n++) {
        inspector
          ..onRequest(createRequestEvent(
              requestId: 'r$n',
              uri: Uri.parse('http://localhost/api/v1/rooms')))
          ..onResponse(createResponseEvent(requestId: 'r$n'));
      }

      // The narrowest supported width at an accessibility text size, pumped
      // without the screen around it: HomeShellHeader overflows on its own
      // account here, and would fail this test for a fault it does not own.
      const size = Size(SoliplexBreakpoints.mobile, 800);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
          home: MediaQuery(
            data: const MediaQueryData(
              size: size,
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(
              body: RequestsPane(
                inspector: inspector,
                onRunFilterCleared: () {},
                viewSwitcher: const SizedBox(height: 48),
                filtersExpanded: true,
                onFiltersExpandedToggled: () {},
                // UUID-shaped, which is what the backend sends: the run
                // scope's row is squeezed here as hard as the heading's.
                runId: '3f8a1c2e-9b4d-4f6a-8e21-77c0d5b9a1f3',
              ),
            ),
          ),
        ),
      );

      // Nothing in these rows may push its neighbour off the edge. A test
      // fails on an overflow, so rendering them at this size is the
      // assertion.
      expect(find.textContaining('Requests ('), findsOneWidget);
      expect(find.text('Hide filters'), findsOneWidget);
      expect(find.textContaining('Run · '), findsOneWidget);
    });
  });
}
