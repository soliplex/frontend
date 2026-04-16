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
        MaterialApp(home: NetworkInspectorScreen(inspector: inspector)),
      );
      expect(find.text('No HTTP requests yet'), findsOneWidget);
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
        MaterialApp(home: NetworkInspectorScreen(inspector: inspector)),
      );
      expect(find.text('GET'), findsOneWidget);
    });

    testWidgets('clear button is disabled when no events', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NetworkInspectorScreen(inspector: inspector)),
      );
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('clear button is enabled when events exist', (tester) async {
      inspector.onRequest(createRequestEvent());
      await tester.pumpWidget(
        MaterialApp(home: NetworkInspectorScreen(inspector: inspector)),
      );
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('clear button clears events and shows empty state',
        (tester) async {
      inspector.onRequest(createRequestEvent());

      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(home: NetworkInspectorScreen(inspector: inspector)),
      );

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(find.text('No HTTP requests yet'), findsOneWidget);
    });

    testWidgets('clear button is enabled when only concurrency events exist',
        (tester) async {
      inspector.onConcurrencyWait(createConcurrencyWaitEvent());

      await tester.pumpWidget(
        MaterialApp(home: NetworkInspectorScreen(inspector: inspector)),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
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
        MaterialApp(home: NetworkInspectorScreen(inspector: inspector)),
      );

      // Panel is visible when concurrency events exist.
      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);

      await tester.tap(find.byType(IconButton));
      await tester.pump();

      // Panel hides itself when the list is empty.
      expect(find.byIcon(Icons.hourglass_empty), findsNothing);
      expect(inspector.concurrencyEvents, isEmpty);
    });
  });
}
