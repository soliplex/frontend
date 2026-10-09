import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/execution_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/phase_indicator.dart';
import 'package:soliplex_frontend/src/modules/room/ui/execution/thinking_block.dart';
import 'package:soliplex_frontend/src/modules/room/ui/message_caption.dart';
import 'package:soliplex_frontend/src/modules/room/ui/no_response_tile_widget.dart';

import '../../../helpers/test_logger.dart';

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
    switch (reason) {
      TerminalReason.failed => NoResponseTile.failed(
          runId: 'run-1',
          createdAt: DateTime(2026),
          thinkingText: thinkingText,
          errorDetail: errorDetail ?? '',
        ),
      TerminalReason.cancelled => NoResponseTile.cancelled(
          runId: 'run-1',
          createdAt: DateTime(2026),
          thinkingText: thinkingText,
        ),
      TerminalReason.finished => NoResponseTile.finished(
          runId: 'run-1',
          createdAt: DateTime(2026),
          thinkingText: thinkingText,
        ),
    };

void main() {
  testWidgets('shows a timestamp caption', (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: NoResponseTile.finished(
          runId: 'run-1',
          createdAt: DateTime(2020, 3, 3, 9, 3),
          thinkingText: 'thinking',
        ),
      ),
    ));

    expect(find.byType(MessageCaption), findsOneWidget);
    expect(find.text('Mar 3, 2020 · 9:03 AM'), findsOneWidget);
  });

  testWidgets('finished renders the info icon', (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: _tile(reason: TerminalReason.finished),
      ),
    ));

    expect(find.byIcon(Icons.info_outline), findsOneWidget);
  });

  testWidgets('failed without detail says the run gave no response',
      (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: _tile(reason: TerminalReason.failed),
      ),
    ));

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('Run failed without a response'), findsOneWidget);
    expect(find.byTooltip('Copy'), findsNothing);
  });

  testWidgets('failed with detail renders "Run failed: <error>"',
      (tester) async {
    await tester.pumpWidget(_wrap(
      NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
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
        besideReply: false,
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
        besideReply: false,
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
        besideReply: false,
        message: _tile(reason: TerminalReason.failed, thinkingText: ''),
      ),
    ));

    expect(find.text('Thinking...'), findsNothing);
  });

  testWidgets(
      'beside a reply shows the reason, the note and the time, and leaves the '
      "author, the run's work and its reasoning to the reply", (tester) async {
    final band = ExecutionTracker(
      activities: Signal<List<ActivityRecord>>(const []),
      logger: testLogger(),
    );
    addTearDown(band.dispose);
    band.observe(const ThinkingStarted());
    band.observe(const ThinkingContent(delta: 'reasoning...'));
    band.observe(
      const ServerToolCallStarted(toolName: 'search', toolCallId: 'tc-1'),
    );

    await tester.pumpWidget(_wrap(NoResponseTileWidget(
      roomId: 'r',
      besideReply: true,
      executionTracker: band,
      streamingPhase: const RespondingPhase(),
      message: NoResponseTile.failed(
        runId: 'run-1',
        createdAt: DateTime(2020, 3, 3, 9, 3),
        thinkingText: 'reasoning',
        errorDetail: 'upstream said no',
      ),
      runId: 'run-1',
      onReportRun: (_) {},
    )));

    expect(find.text('Run failed: upstream said no'), findsOneWidget);
    expect(find.text('View or add a note'), findsOneWidget);
    expect(find.text('Mar 3, 2020 · 9:03 AM'), findsOneWidget);
    expect(find.text('Assistant'), findsNothing);
    expect(find.text('Thinking...'), findsNothing);
    expect(find.byType(ExecutionTimeline), findsNothing);
    expect(find.byType(ExecutionThinkingBlock), findsNothing);
    expect(find.byType(PhaseIndicator), findsNothing);
  });

  testWidgets(
      'beside a reply, a failure with only blank detail says only that the '
      'run failed', (tester) async {
    // The reply above it is a response, so the generic copy would deny it.
    await tester.pumpWidget(_wrap(NoResponseTileWidget(
      roomId: 'r',
      besideReply: true,
      message: _tile(reason: TerminalReason.failed, errorDetail: '  '),
    )));

    expect(find.text('Run failed'), findsOneWidget);
    expect(find.text('Run failed without a response'), findsNothing);
    expect(find.byTooltip('Copy'), findsNothing);
  });

  for (final besideReply in [false, true]) {
    testWidgets(
        'a failure copies its detail, without the label '
        '(besideReply: $besideReply)', (tester) async {
      String? copied;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(_wrap(NoResponseTileWidget(
        roomId: 'r',
        besideReply: besideReply,
        message: _tile(
          reason: TerminalReason.failed,
          errorDetail: 'rate limit exceeded',
        ),
      )));

      await tester.tap(find.byTooltip('Copy'));
      await tester.pump();

      expect(copied, 'rate limit exceeded');
    });
  }

  group('report affordance', () {
    testWidgets('failed offers reading or adding to the filed note',
        (tester) async {
      await tester.pumpWidget(_wrap(NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: _tile(reason: TerminalReason.failed),
        runId: 'run-1',
        onReportRun: (_) {},
      )));

      expect(find.text('View or add a note'), findsOneWidget);
    });

    testWidgets('finished offers reporting a problem', (tester) async {
      await tester.pumpWidget(_wrap(NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: _tile(reason: TerminalReason.finished),
        runId: 'run-1',
        onReportRun: (_) {},
      )));

      expect(find.text('Report a problem'), findsOneWidget);
    });

    testWidgets('cancelled offers nothing — it was the user\'s own stop',
        (tester) async {
      await tester.pumpWidget(_wrap(NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: _tile(reason: TerminalReason.cancelled),
        runId: 'run-1',
        onReportRun: (_) {},
      )));

      expect(find.text('View or add a note'), findsNothing);
      expect(find.text('Report a problem'), findsNothing);
    });

    testWidgets('offers nothing without a run to file against', (tester) async {
      await tester.pumpWidget(_wrap(NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: _tile(reason: TerminalReason.failed),
        onReportRun: (_) {},
      )));

      expect(find.text('View or add a note'), findsNothing);
    });

    testWidgets('reports the run the tile belongs to', (tester) async {
      final reported = <String>[];
      await tester.pumpWidget(_wrap(NoResponseTileWidget(
        roomId: 'r',
        besideReply: false,
        message: _tile(reason: TerminalReason.failed),
        runId: 'run-7',
        onReportRun: reported.add,
      )));

      await tester.tap(find.text('View or add a note'));
      await tester.pump();

      expect(reported, ['run-7']);
    });
  });
}
