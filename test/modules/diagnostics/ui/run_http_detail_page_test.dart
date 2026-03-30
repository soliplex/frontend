import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/http_event_group.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/request_detail_view.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/ui/run_http_detail_page.dart';

import '../../../helpers/http_event_factories.dart';

void main() {
  group('RunHttpDetailPage', () {
    testWidgets('shows empty state when groups is empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: RunHttpDetailPage(groups: [])),
      );
      expect(find.text('No HTTP traffic found for this run'), findsOneWidget);
    });

    testWidgets('shows RequestDetailView directly when single group',
        (tester) async {
      final group = HttpEventGroup(
        requestId: 'req-1',
        request: createRequestEvent(),
        response: createResponseEvent(),
      );
      await tester.pumpWidget(
        MaterialApp(home: RunHttpDetailPage(groups: [group])),
      );
      expect(find.byType(RequestDetailView), findsOneWidget);
    });

    testWidgets('shows list of tiles when multiple groups', (tester) async {
      final groups = [
        HttpEventGroup(
          requestId: 'req-1',
          request: createRequestEvent(
            requestId: 'req-1',
            uri: Uri.parse('http://localhost/api/v1/rooms'),
          ),
          response: createResponseEvent(requestId: 'req-1'),
        ),
        HttpEventGroup(
          requestId: 'req-2',
          request: createRequestEvent(
            requestId: 'req-2',
            uri: Uri.parse('http://localhost/api/v1/users'),
          ),
          response: createResponseEvent(requestId: 'req-2'),
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(home: RunHttpDetailPage(groups: groups)),
      );
      // AppBar shows count
      expect(find.text('HTTP Traffic (2)'), findsOneWidget);
      // Both paths listed
      expect(find.text('/api/v1/rooms'), findsOneWidget);
      expect(find.text('/api/v1/users'), findsOneWidget);
    });
  });
}
