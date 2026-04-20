import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' show FeedbackType;

import 'package:soliplex_frontend/src/modules/room/ui/feedback_buttons.dart';

void main() {
  testWidgets('tapping thumb up starts countdown and auto-submits', (
    tester,
  ) async {
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
}
