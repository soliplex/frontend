import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/overview_tab.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('OverviewTab', () {
    testWidgets(
        'shows empty state when no request body, response body, or SSE body',
        (tester) async {
      final group = HttpEventGroup(requestId: 'req-1');
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OverviewTab(group: group))),
      );
      expect(find.text('No structured content available'), findsOneWidget);
    });

    testWidgets('shows request body section when request has a body',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(body: '{"key": "value"}'),
        response: createResponseEvent(body: null),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OverviewTab(group: group))),
      );
      expect(find.text('Request Body'), findsOneWidget);
    });

    testWidgets('shows response body section when response has a body',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(body: '{"result": "ok"}'),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OverviewTab(group: group))),
      );
      expect(find.text('Response Body'), findsOneWidget);
    });

    testWidgets('shows stream section with toggle when SSE stream',
        (tester) async {
      final sseBody = 'data: {"type":"RUN_STARTED"}\n'
          'data: {"type":"TEXT_MESSAGE_START","messageId":"m1","role":"assistant"}\n'
          'data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"Hello"}\n'
          'data: {"type":"TEXT_MESSAGE_END","messageId":"m1"}\n'
          'data: {"type":"RUN_FINISHED"}\n';

      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(body: sseBody),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OverviewTab(group: group))),
      );
      expect(find.text('Stream'), findsOneWidget);
      expect(find.text('Conversation'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
    });

    testWidgets(
        'shows truncation banner when SSE body starts with truncation marker',
        (tester) async {
      final sseBody = '[EARLIER CONTENT DROPPED]\n'
          'data: {"type":"RUN_FINISHED"}\n';

      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(body: sseBody),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OverviewTab(group: group))),
      );
      expect(
        find.text('Earlier stream content was truncated'),
        findsOneWidget,
      );
    });

    testWidgets('conversation view shows assembled message entries',
        (tester) async {
      final sseBody = 'data: {"type":"RUN_STARTED"}\n'
          'data: {"type":"TEXT_MESSAGE_START","messageId":"m1","role":"assistant"}\n'
          'data: {"type":"TEXT_MESSAGE_CONTENT","messageId":"m1","delta":"Hello"}\n'
          'data: {"type":"TEXT_MESSAGE_END","messageId":"m1"}\n'
          'data: {"type":"RUN_FINISHED"}\n';

      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(body: sseBody),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OverviewTab(group: group))),
      );
      // Conversation view (default) should show assembled role label
      expect(find.text('ASSISTANT'), findsOneWidget);
    });

    testWidgets('events view shows individual SSE events after toggle',
        (tester) async {
      final sseBody = 'data: {"type":"RUN_STARTED"}\n'
          'data: {"type":"RUN_FINISHED"}\n';

      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(body: sseBody),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: OverviewTab(group: group))),
      );

      // Tap "Events" in the segmented button
      await tester.tap(find.text('Events'));
      await tester.pump();

      // Individual SSE event type badges should appear
      expect(find.text('RUN_STARTED'), findsOneWidget);
      expect(find.text('RUN_FINISHED'), findsOneWidget);
    });
  });
}
