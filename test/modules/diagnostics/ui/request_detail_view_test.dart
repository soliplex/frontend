import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/request_detail_view.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('RequestDetailView', () {
    testWidgets('shows all 4 tabs', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
      expect(find.text('curl'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
    });

    testWidgets('shows search bar with text field', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      expect(find.byType(TextField), findsOneWidget);
      expect(find.widgetWithText(TextField, ''), findsOneWidget);
    });

    testWidgets('request tab shows headers and body when present',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(
          headers: {'Content-Type': 'application/json'},
          body: '{"key": "value"}',
        ),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      expect(find.text('Headers'), findsOneWidget);
      expect(find.text('Body'), findsOneWidget);
    });

    testWidgets('request tab shows empty state when no headers or body',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(headers: {}, body: null),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      expect(find.text('No request headers or body'), findsOneWidget);
    });

    testWidgets('response tab shows waiting state when no response',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      // Navigate to Response tab
      await tester.tap(find.text('Response'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Waiting for response...'), findsOneWidget);
    });

    testWidgets('response tab shows error display for network errors',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        error: createErrorEvent(
          exception: const NetworkException(message: 'Connection refused'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      await tester.tap(find.text('Response'));
      await tester.pumpAndSettle();
      expect(find.text('Connection refused'), findsOneWidget);
    });

    testWidgets('response tab shows stream in progress state', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      await tester.tap(find.text('Response'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Stream in progress...'), findsOneWidget);
    });

    testWidgets('curl tab shows curl command when request data is present',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(
          method: 'GET',
          uri: Uri.parse('http://localhost/api/v1/rooms'),
        ),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      await tester.tap(find.text('curl'));
      await tester.pumpAndSettle();
      expect(find.text('curl command'), findsOneWidget);
      expect(find.textContaining('curl'), findsWidgets);
    });

    testWidgets('curl tab shows unavailable message when no request data',
        (tester) async {
      // Use an error event — group has method/uri for the summary header,
      // but toCurl() returns null because there is no request/streamStart.
      final group = HttpEventGroup(
        requestId: 'req-1',
        error: createErrorEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: RequestDetailView(group: group))),
      );
      await tester.tap(find.text('curl'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        find.text('curl command unavailable - no request data'),
        findsOneWidget,
      );
    });
  });
}
