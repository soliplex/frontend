import 'dart:async';

import 'package:file_picker/file_picker.dart';
// ignore: implementation_imports
import 'package:file_picker/src/platform/file_picker_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/network_inspector.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/diagnostics_screen.dart';

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

      await tester.tap(find.text('Clear filters'));
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
}
