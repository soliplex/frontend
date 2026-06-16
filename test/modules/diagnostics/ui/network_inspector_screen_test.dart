import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/network_inspector.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/network_inspector_screen.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('NetworkInspectorScreen', () {
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
            home: NetworkInspectorScreen(
                appName: 'Soliplex', inspector: inspector)),
      );
      expect(find.text('No HTTP requests yet'), findsOneWidget);
    });

    testWidgets('shows the branded bar (no about button) and back affordance',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkInspectorScreen(appName: 'Acme', inspector: inspector),
        ),
      );

      // Branded app name in the bar; the about/versions button is dropped.
      expect(find.text('Acme'), findsOneWidget);
      expect(find.byTooltip('About & versions'), findsNothing);
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
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home: NetworkInspectorScreen(appName: 'Acme', inspector: inspector),
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
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
            home: NetworkInspectorScreen(
                appName: 'Soliplex', inspector: inspector)),
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
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          home:
              NetworkInspectorScreen(appName: 'Soliplex', inspector: inspector),
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
            home: NetworkInspectorScreen(
                appName: 'Soliplex', inspector: inspector)),
      );
      final button = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.delete_sweep_outlined));
      expect(button.onPressed, isNull);
    });

    testWidgets('clear button is enabled when events exist', (tester) async {
      inspector.onRequest(createRequestEvent());
      await tester.pumpWidget(
        MaterialApp(
            home: NetworkInspectorScreen(
                appName: 'Soliplex', inspector: inspector)),
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
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
            home: NetworkInspectorScreen(
                appName: 'Soliplex', inspector: inspector)),
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
            home: NetworkInspectorScreen(
                appName: 'Soliplex', inspector: inspector)),
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
            home: NetworkInspectorScreen(
                appName: 'Soliplex', inspector: inspector)),
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
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(
          home: NetworkInspectorScreen(
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
}
