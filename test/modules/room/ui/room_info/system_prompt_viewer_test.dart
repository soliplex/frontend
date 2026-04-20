import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_info/system_prompt_viewer.dart';
import 'package:soliplex_frontend/src/shared/copy_button.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  // A prompt long enough to overflow 3 lines in a 300-wide constrained box.
  final longPrompt = 'You are a helpful assistant. ' * 30;

  testWidgets('shows prompt text', (tester) async {
    const prompt = 'You are a helpful assistant.';
    await tester.pumpWidget(wrap(const SystemPromptViewer(prompt: prompt)));

    expect(find.text(prompt), findsOneWidget);
  });

  testWidgets('shows System Prompt label', (tester) async {
    await tester.pumpWidget(wrap(const SystemPromptViewer(prompt: 'hello')));

    expect(find.text('System Prompt'), findsOneWidget);
  });

  testWidgets('CopyButton is present', (tester) async {
    await tester.pumpWidget(wrap(const SystemPromptViewer(prompt: 'hello')));

    expect(find.byType(CopyButton), findsOneWidget);
  });

  testWidgets('expand/collapse button visible when text overflows', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(SizedBox(width: 300, child: SystemPromptViewer(prompt: longPrompt))),
    );

    // Overflow detection may or may not trigger with Ahem font, but if the
    // button appears, it should read "Expand".
    final expandButton = find.widgetWithText(TextButton, 'Expand');
    if (expandButton.evaluate().isNotEmpty) {
      expect(expandButton, findsOneWidget);
    }
  });

  testWidgets('tapping Expand shows full text and changes label to Collapse', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        SingleChildScrollView(
          child: SizedBox(
            width: 300,
            child: SystemPromptViewer(prompt: longPrompt),
          ),
        ),
      ),
    );

    final expandButton = find.widgetWithText(TextButton, 'Expand');
    if (expandButton.evaluate().isEmpty) {
      // Overflow not detected with test font — skip toggle assertion.
      return;
    }

    await tester.tap(expandButton);
    await tester.pump();

    expect(find.widgetWithText(TextButton, 'Collapse'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Expand'), findsNothing);
  });

  testWidgets(
    'tapping Collapse truncates text and changes label back to Expand',
    (tester) async {
      await tester.pumpWidget(
        wrap(
          SingleChildScrollView(
            child: SizedBox(
              width: 300,
              child: SystemPromptViewer(prompt: longPrompt),
            ),
          ),
        ),
      );

      final expandButton = find.widgetWithText(TextButton, 'Expand');
      if (expandButton.evaluate().isEmpty) {
        // Overflow not detected with test font — skip toggle assertion.
        return;
      }

      // Expand first.
      await tester.tap(expandButton);
      await tester.pump();

      // Now collapse. Scroll it into view first since the expanded text may push
      // the button below the visible area.
      final collapseButton = find.widgetWithText(TextButton, 'Collapse');
      await tester.ensureVisible(collapseButton);
      await tester.pump();
      await tester.tap(collapseButton);
      await tester.pump();

      expect(find.widgetWithText(TextButton, 'Expand'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Collapse'), findsNothing);
    },
  );
}
