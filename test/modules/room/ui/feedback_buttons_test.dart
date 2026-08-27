import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show FeedbackType;
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/room/ui/feedback_buttons.dart';

void main() {
  testWidgets('tapping thumb up starts countdown and auto-submits',
      (tester) async {
    FeedbackType? submittedType;
    String? submittedReason;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackButtons(
            onFeedbackSubmit: (type, reason) {
              submittedType = type;
              submittedReason = reason;
            },
            countdownSeconds: 1,
          ),
        ),
      ),
    );

    // Tap thumbs up
    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pump();

    // "Tell us why!" should appear
    expect(find.text('Tell us why!'), findsOneWidget);

    // Wait for countdown to expire
    await tester.pump(const Duration(seconds: 2));

    expect(submittedType, FeedbackType.thumbsUp);
    expect(submittedReason, isNull);
  });

  testWidgets('tapping active thumb during countdown cancels', (tester) async {
    FeedbackType? submittedType;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackButtons(
            onFeedbackSubmit: (type, reason) => submittedType = type,
            countdownSeconds: 5,
          ),
        ),
      ),
    );

    // Tap thumbs up to start countdown
    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pump();
    expect(find.text('Tell us why!'), findsOneWidget);

    // Tap same thumb again to cancel
    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pump();
    expect(find.text('Tell us why!'), findsNothing);
    expect(submittedType, isNull);
  });

  testWidgets('switching direction restarts countdown', (tester) async {
    FeedbackType? submittedType;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackButtons(
            onFeedbackSubmit: (type, reason) => submittedType = type,
            countdownSeconds: 1,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pump();

    // Switch to thumbs down
    await tester.tap(find.byTooltip('Thumbs down'));
    await tester.pump();

    // Wait for countdown
    await tester.pump(const Duration(seconds: 2));
    expect(submittedType, FeedbackType.thumbsDown);
  });

  testWidgets('dispose during countdown auto-submits', (tester) async {
    FeedbackType? submittedType;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackButtons(
            onFeedbackSubmit: (type, reason) => submittedType = type,
            countdownSeconds: 5,
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Thumbs up'));
    await tester.pump();

    // Remove widget (triggers dispose)
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: SizedBox())),
    );

    expect(submittedType, FeedbackType.thumbsUp);
  });

  group('the reason dialog', () {
    /// Pumps the buttons, starts a countdown, and opens the reason dialog.
    Future<List<(FeedbackType, String?)>> openDialog(
      WidgetTester tester,
    ) async {
      final submitted = <(FeedbackType, String?)>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackButtons(
              onFeedbackSubmit: (type, reason) => submitted.add((type, reason)),
              countdownSeconds: 30,
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Thumbs down'));
      await tester.pump();
      await tester.tap(find.text('Tell us why!'));
      await tester.pumpAndSettle();
      return submitted;
    }

    testWidgets('Send submits the typed reason once', (tester) async {
      final submitted = await openDialog(tester);

      await tester.enterText(find.byType(TextField), 'wrong citation');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submitted, [(FeedbackType.thumbsDown, 'wrong citation')]);
      // Submitted, so the countdown must not restart and re-submit.
      await tester.pump(const Duration(seconds: 31));
      expect(submitted, hasLength(1));
    });

    testWidgets('an all-whitespace reason submits as no reason',
        (tester) async {
      final submitted = await openDialog(tester);

      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submitted, [(FeedbackType.thumbsDown, null)]);
    });

    testWidgets('Cancel resumes the countdown instead of submitting',
        (tester) async {
      final submitted = await openDialog(tester);

      await tester.tap(find.text('Cancel'));
      // Bounded pumps: pumpAndSettle would run the resumed countdown to
      // completion and submit, which is the behaviour under test.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(submitted, isEmpty);
      expect(find.text('Tell us why!'), findsOneWidget);

      await tester.pump(const Duration(seconds: 31));
      expect(submitted, [(FeedbackType.thumbsDown, null)]);
    });

    testWidgets('a send after the tile is gone refuses instead of throwing',
        (tester) async {
      // The tile lives in a sliver, so it can be destroyed while the modal is
      // still up. Submitting then reaches setState on a defunct State, which
      // throws — the dialog's guard would swallow it as a caller defect and
      // log at error level, burying the real defects that log is for.
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      final submitted = <(FeedbackType, String?)>[];
      final showTile = ValueNotifier<bool>(true);
      addTearDown(showTile.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: showTile,
              builder: (_, visible, __) => visible
                  ? FeedbackButtons(
                      onFeedbackSubmit: (type, reason) =>
                          submitted.add((type, reason)),
                      countdownSeconds: 30,
                    )
                  : const SizedBox.shrink(),
            ),
          ),
        ),
      );
      await tester.tap(find.byTooltip('Thumbs down'));
      await tester.pump();
      await tester.tap(find.text('Tell us why!'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'typed after teardown');

      // Drop the tile, keeping the dialog's route on the navigator above it.
      showTile.value = false;
      await tester.pump();

      await tester.tap(find.text('Send'));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        sink.records.where((r) => r.level >= LogLevel.error),
        isEmpty,
        reason: 'An expected teardown must not be logged as a caller defect.',
      );
      // dispose already submitted for the pending direction; the reason typed
      // after teardown cannot be delivered, and the dialog says so.
      expect(submitted, [(FeedbackType.thumbsDown, null)]);
      expect(find.text("Couldn't send that. Try again."), findsOneWidget);
    });
  });
}
