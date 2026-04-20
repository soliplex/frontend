import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_info/features_card.dart';

import '../../../../helpers/fakes.dart';

/// FakeSoliplexApi subclass that can stall getMcpToken until a completer
/// is resolved, enabling loading-state tests.
class _ControllableMcpApi extends FakeSoliplexApi {
  Completer<String>? getMcpTokenCompleter;

  @override
  Future<String> getMcpToken(String roomId, {CancelToken? cancelToken}) {
    if (getMcpTokenCompleter != null) return getMcpTokenCompleter!.future;
    return super.getMcpToken(roomId, cancelToken: cancelToken);
  }
}

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  const baseRoom = Room(id: 'r1', name: 'Test Room');

  group('FeaturesCard', () {
    testWidgets('shows attachments status row', (tester) async {
      final api = FakeSoliplexApi();
      await tester.pumpWidget(
        wrap(
          FeaturesCard(
            room: baseRoom.copyWith(enableAttachments: true),
            api: api,
            roomId: 'r1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Attachments'), findsOneWidget);
      expect(find.text('Enabled'), findsOneWidget);
    });

    testWidgets('shows attachments disabled', (tester) async {
      final api = FakeSoliplexApi();
      await tester.pumpWidget(
        wrap(
          FeaturesCard(
            room: baseRoom.copyWith(enableAttachments: false),
            api: api,
            roomId: 'r1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Disabled'), findsOneWidget);
    });

    testWidgets('shows MCP row when allowMcp is true', (tester) async {
      final api = FakeSoliplexApi();
      await tester.pumpWidget(
        wrap(
          FeaturesCard(
            room: baseRoom.copyWith(allowMcp: true),
            api: api,
            roomId: 'r1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Allow MCP'), findsOneWidget);
      expect(find.text('Yes'), findsOneWidget);
    });

    testWidgets('hides MCP token row when allowMcp is false', (tester) async {
      final api = FakeSoliplexApi();
      await tester.pumpWidget(
        wrap(
          FeaturesCard(
            room: baseRoom.copyWith(allowMcp: false),
            api: api,
            roomId: 'r1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('No'), findsOneWidget);
      // McpTokenRow should not be present
      expect(find.byType(McpTokenRow), findsNothing);
    });

    testWidgets('shows McpTokenRow when allowMcp is true', (tester) async {
      final api = FakeSoliplexApi();
      await tester.pumpWidget(
        wrap(
          FeaturesCard(
            room: baseRoom.copyWith(allowMcp: true),
            api: api,
            roomId: 'r1',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(McpTokenRow), findsOneWidget);
    });

    testWidgets('shows AG-UI features row when aguiFeatureNames non-empty', (
      tester,
    ) async {
      final api = FakeSoliplexApi();
      await tester.pumpWidget(
        wrap(
          FeaturesCard(
            room: baseRoom.copyWith(
              aguiFeatureNames: ['feature-a', 'feature-b'],
            ),
            api: api,
            roomId: 'r1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('AG-UI Features'), findsOneWidget);
      expect(find.text('feature-a, feature-b'), findsOneWidget);
    });

    testWidgets('hides AG-UI features row when aguiFeatureNames is empty', (
      tester,
    ) async {
      final api = FakeSoliplexApi();
      await tester.pumpWidget(
        wrap(
          FeaturesCard(
            room: baseRoom.copyWith(aguiFeatureNames: []),
            api: api,
            roomId: 'r1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('AG-UI Features'), findsNothing);
    });
  });

  group('McpTokenRow', () {
    testWidgets('shows loading indicator while fetching token', (tester) async {
      final api = _ControllableMcpApi();
      api.getMcpTokenCompleter = Completer<String>();

      await tester.pumpWidget(wrap(McpTokenRow(api: api, roomId: 'r1')));
      // Don't pump the future — stay in loading state
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Clean up: complete future to avoid pending timers
      api.getMcpTokenCompleter!.complete('token');
      await tester.pump();
    });

    testWidgets('shows copy button after token loaded successfully', (
      tester,
    ) async {
      final api = FakeSoliplexApi();
      api.nextMcpToken = 'my-secret-token';

      await tester.pumpWidget(wrap(McpTokenRow(api: api, roomId: 'r1')));
      await tester.pump(); // let the future complete

      expect(find.text('Copy Token'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('shows retry button when token fetch fails', (tester) async {
      final api = FakeSoliplexApi();
      api.nextMcpTokenError = Exception('network error');

      await tester.pumpWidget(wrap(McpTokenRow(api: api, roomId: 'r1')));
      await tester.pump(); // let the future resolve with error

      expect(find.text('Retry token'), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsOneWidget);
    });

    testWidgets('copy button shows success state then resets after 2s', (
      tester,
    ) async {
      final api = FakeSoliplexApi();
      api.nextMcpToken = 'my-secret-token';

      // Set up a fake clipboard to avoid platform exceptions
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall call) async {
          if (call.method == 'Clipboard.setData') return null;
          return null;
        },
      );

      await tester.pumpWidget(wrap(McpTokenRow(api: api, roomId: 'r1')));
      await tester.pump(); // let the future complete

      expect(find.text('Copy Token'), findsOneWidget);

      await tester.tap(find.text('Copy Token'));
      await tester.pump(); // let setState run

      expect(find.text('Copied'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Advance past the 2-second reset timer
      await tester.pump(const Duration(seconds: 2));

      expect(find.text('Copy Token'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);

      // Clean up mock
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });
  });
}
