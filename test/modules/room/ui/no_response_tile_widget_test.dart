import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/no_response_tile_widget.dart';

Widget _wrap(Widget child, {MessageExpansions? store}) => ProviderScope(
      overrides: [
        messageExpansionsProvider
            .overrideWithValue(store ?? MessageExpansions()),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );

NoResponseTile _tile({
  required TerminalReason reason,
  String thinkingText = 'reasoning',
  String? errorDetail,
}) =>
    NoResponseTile(
      id: 'no-response-run-1',
      createdAt: DateTime(2026),
      thinkingText: thinkingText,
      reason: reason,
      errorDetail: errorDetail,
    );

void main() {
  testWidgets('finished renders the info icon', (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        message: _tile(reason: TerminalReason.finished),
      ),
    ));

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('failed without detail renders the error icon', (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        message: _tile(reason: TerminalReason.failed),
      ),
    ));

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('failed with detail renders "Run failed: <error>"',
      (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        message: _tile(
          reason: TerminalReason.failed,
          errorDetail: 'rate limit exceeded',
        ),
      ),
    ));

    expect(find.text('Run failed: rate limit exceeded'), findsOneWidget);
    expect(
      find.text('Run failed without a response'),
      findsNothing,
      reason: 'detail must replace the generic copy, not append to it',
    );
  });

  testWidgets('cancelled renders the cancel icon', (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        message: _tile(reason: TerminalReason.cancelled),
      ),
    ));

    expect(find.byIcon(Icons.cancel_outlined), findsOneWidget);
  });

  testWidgets('thinking text is displayed in an expansion tile',
      (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        message: _tile(
          reason: TerminalReason.cancelled,
          thinkingText: 'I considered the options',
        ),
      ),
    ));

    expect(find.text('Thinking...'), findsOneWidget);
    await tester.tap(find.text('Thinking...'));
    await tester.pumpAndSettle();
    expect(find.text('I considered the options'), findsOneWidget);
  });

  testWidgets('empty thinking text hides the thinking block', (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        message: _tile(reason: TerminalReason.failed, thinkingText: ''),
      ),
    ));

    expect(find.text('Thinking...'), findsNothing);
  });
}
