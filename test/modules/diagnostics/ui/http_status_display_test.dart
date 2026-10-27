import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/http_status_display.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('HttpStatusDisplay', () {
    testWidgets('shows pending text when no response', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      expect(find.text('pending...'), findsOneWidget);
    });

    testWidgets('shows status code, duration, and size for successful response',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(
          statusCode: 200,
          duration: const Duration(milliseconds: 45),
          bodySize: 1234,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      // Status text contains "200 OK"
      expect(find.textContaining('200 OK'), findsOneWidget);
    });

    testWidgets('shows streaming text when stream is in progress',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      expect(find.textContaining('streaming...'), findsOneWidget);
    });

    testWidgets('shows complete with duration for finished stream',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(
          duration: const Duration(seconds: 10),
          bytesReceived: 5200,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      expect(find.textContaining('complete'), findsOneWidget);
    });

    testWidgets('shows the status code of a refused stream', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(bytesReceived: 0, statusCode: 403),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      expect(find.textContaining('403 ('), findsOneWidget);
    });

    testWidgets('shows error for a stream that failed after it was accepted',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(
          statusCode: 200,
          error: const NetworkException(message: 'Connection lost'),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      expect(find.textContaining('error ('), findsOneWidget);
    });

    testWidgets('shows spinner for pending state', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows no spinner for completed response', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(statusCode: 200),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpStatusDisplay(group: group))),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });
  });
}
