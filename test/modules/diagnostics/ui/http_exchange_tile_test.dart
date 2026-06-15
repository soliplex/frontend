import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/http_exchange_tile.dart';

import '../../../helpers/http_event_factories.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('HttpExchangeTile', () {
    testWidgets('collapsed by default; expands on tap', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(method: 'GET'),
        response: createResponseEvent(),
      );

      await tester.pumpWidget(_wrap(HttpExchangeTile(group: group)));

      expect(find.text('Summary'), findsNothing);
      await tester.tap(find.text('GET'));
      await tester.pumpAndSettle();

      expect(find.text('Summary'), findsOneWidget);
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Response'), findsOneWidget);
    });

    testWidgets('initiallyExpanded shows detail without a tap', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(),
      );

      await tester.pumpWidget(
        _wrap(HttpExchangeTile(group: group, initiallyExpanded: true)),
      );

      expect(find.text('Summary'), findsOneWidget);
    });

    testWidgets('offers a JSON⇄Raw toggle for a JSON body', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(body: '{"hello":"world"}'),
      );

      await tester.pumpWidget(
        _wrap(HttpExchangeTile(group: group, initiallyExpanded: true)),
      );

      // The segmented toggle exists for the parseable response body.
      expect(find.text('JSON'), findsOneWidget);
      expect(find.text('Raw'), findsOneWidget);
    });

    testWidgets('shows a Copy as curl action', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(method: 'POST'),
        response: createResponseEvent(),
      );

      await tester.pumpWidget(
        _wrap(HttpExchangeTile(group: group, initiallyExpanded: true)),
      );

      expect(find.text('Copy as curl'), findsOneWidget);
    });

    testWidgets('renders an error response distinctly', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(method: 'POST'),
        error: createErrorEvent(),
      );

      await tester.pumpWidget(
        _wrap(HttpExchangeTile(group: group, initiallyExpanded: true)),
      );

      expect(find.text('Connection failed'), findsOneWidget);
    });

    testWidgets('plain-text body shows no JSON toggle', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(body: 'not json at all'),
      );

      await tester.pumpWidget(
        _wrap(HttpExchangeTile(group: group, initiallyExpanded: true)),
      );

      expect(find.text('not json at all'), findsOneWidget);
      expect(find.text('JSON'), findsNothing);
    });

    testWidgets('stream response offers Conversation/Events/Raw views',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        streamStart: createStreamStartEvent(),
        streamEnd: createStreamEndEvent(
          body: 'event: message\ndata: {"role":"assistant"}\n\n',
        ),
      );

      await tester.pumpWidget(
        _wrap(HttpExchangeTile(group: group, initiallyExpanded: true)),
      );

      // Summary records the stream flag, and the response hosts the toggle.
      expect(find.text('Conversation'), findsOneWidget);
      expect(find.text('Events'), findsOneWidget);
    });

    testWidgets('tabular header renders the endpoint path', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(
          uri: Uri.parse('http://localhost/api/v1/rooms'),
        ),
        response: createResponseEvent(),
      );

      await tester
          .pumpWidget(_wrap(HttpExchangeTile(group: group, tabular: true)));

      expect(find.text('/api/v1/rooms'), findsOneWidget);
    });
  });
}
