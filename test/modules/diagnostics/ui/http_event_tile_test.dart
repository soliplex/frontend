import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/http_event_tile.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('HttpEventTile', () {
    testWidgets('shows method label and path', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(
          method: 'POST',
          uri: Uri.parse('http://localhost/api/v1/rooms'),
        ),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpEventTile(group: group))),
      );
      expect(find.text('POST'), findsOneWidget);
      expect(find.text('/api/v1/rooms'), findsOneWidget);
    });

    testWidgets('dense mode renders without overflow', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(method: 'GET'),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: HttpEventTile(group: group, dense: true)),
        ),
      );
      // Dense mode: timestamp row is omitted
      expect(find.text('GET'), findsOneWidget);
      // No overflow errors — just verify it renders
      expect(tester.takeException(), isNull);
    });

    testWidgets('onTap callback fires when tapped', (tester) async {
      var tapped = false;
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HttpEventTile(group: group, onTap: () => tapped = true),
          ),
        ),
      );
      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('no onTap wraps content without InkWell', (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: HttpEventTile(group: group))),
      );
      // Without onTap, no InkWell is present
      expect(find.byType(InkWell), findsNothing);
    });
  });
}
