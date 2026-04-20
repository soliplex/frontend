import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/feedback_reason_dialog.dart';

void main() {
  testWidgets('renders dialog with text field and actions', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: FeedbackReasonDialog())),
    );

    expect(find.text('Tell us why'), findsOneWidget);
    expect(find.text('Add a reason (optional)'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('Send returns entered text', (tester) async {
    String? result;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (_) => const FeedbackReasonDialog(),
                    );
                  },
                  child: const Text('Open'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Bad citation');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(result, 'Bad citation');
  });

  testWidgets('Cancel returns null', (tester) async {
    String? result = 'sentinel';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<String>(
                      context: context,
                      builder: (_) => const FeedbackReasonDialog(),
                    );
                  },
                  child: const Text('Open'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });
}
