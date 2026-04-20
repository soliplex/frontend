import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/async_action_dialog.dart';

void main() {
  group('AsyncActionDialog', () {
    testWidgets('action button triggers onAction callback', (tester) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => AsyncActionDialog(
                                title: 'Test',
                                contentBuilder: (_) => const Text('body'),
                                actionLabel: 'Go',
                                onAction: () async => called = true,
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });

    testWidgets('shows spinner while action is in progress', (tester) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => AsyncActionDialog(
                                title: 'Test',
                                contentBuilder: (_) => const Text('body'),
                                actionLabel: 'Go',
                                onAction: () => completer.future,
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Go'), findsNothing);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('Cancel is disabled while action is in progress', (
      tester,
    ) async {
      final completer = Completer<void>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => AsyncActionDialog(
                                title: 'Test',
                                contentBuilder: (_) => const Text('body'),
                                actionLabel: 'Go',
                                onAction: () => completer.future,
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Go'));
      await tester.pump();

      final cancelButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Cancel'),
      );
      expect(cancelButton.onPressed, isNull);

      completer.complete();
      await tester.pumpAndSettle();
    });

    testWidgets('shows inline error on Exception', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => AsyncActionDialog(
                                title: 'Test',
                                contentBuilder: (_) => const Text('body'),
                                actionLabel: 'Go',
                                onAction:
                                    () async =>
                                        throw Exception('something went wrong'),
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.textContaining('something went wrong'), findsOneWidget);
      // Dialog should still be open (not popped)
      expect(find.text('Test'), findsOneWidget);
      // Action button should be re-enabled for retry
      expect(find.text('Go'), findsOneWidget);
    });

    testWidgets('pops dialog on success', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => AsyncActionDialog(
                                title: 'Test',
                                contentBuilder: (_) => const Text('body'),
                                actionLabel: 'Go',
                                onAction: () async {},
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Test'), findsOneWidget);

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();

      expect(find.text('Test'), findsNothing);
    });

    testWidgets('action button disabled when canSubmit is false', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => AsyncActionDialog(
                                title: 'Test',
                                contentBuilder: (_) => const Text('body'),
                                actionLabel: 'Go',
                                canSubmit: false,
                                onAction: () async {},
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final actionButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Go'),
      );
      expect(actionButton.onPressed, isNull);
    });

    testWidgets('destructive style applies error color to action button', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => AsyncActionDialog(
                                title: 'Delete',
                                contentBuilder: (_) => const Text('body'),
                                actionLabel: 'Delete',
                                isDestructive: true,
                                onAction: () async {},
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final actionButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Delete'),
      );
      final theme = Theme.of(tester.element(find.text('Delete').last));
      // The button style should set foreground to error color
      expect(actionButton.style, isNotNull);
      final resolved = actionButton.style!.foregroundColor!.resolve(
        <WidgetState>{},
      );
      expect(resolved, theme.colorScheme.error);
    });
  });

  group('RenameDialog', () {
    testWidgets('Save is disabled when text matches initial name', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => RenameDialog(
                                initialName: 'Original',
                                onAction: (_) async {},
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Save is disabled when text is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => RenameDialog(
                                initialName: 'Original',
                                onAction: (_) async {},
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Clear the text field
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Save is disabled when text is whitespace only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => RenameDialog(
                                initialName: 'Original',
                                onAction: (_) async {},
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '   ');
      await tester.pump();

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNull);
    });

    testWidgets('Save is enabled when text differs from initial', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => RenameDialog(
                                initialName: 'Original',
                                onAction: (_) async {},
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New Name');
      await tester.pump();

      final saveButton = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Save'),
      );
      expect(saveButton.onPressed, isNotNull);
    });

    testWidgets('pressing Enter submits when Save is enabled', (tester) async {
      String? submittedName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => RenameDialog(
                                initialName: 'Original',
                                onAction: (name) async => submittedName = name,
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'New Name');
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(submittedName, 'New Name');
    });

    testWidgets('pressing Enter does nothing when Save is disabled', (
      tester,
    ) async {
      bool called = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => RenameDialog(
                                initialName: 'Original',
                                onAction: (_) async => called = true,
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Text matches initial name — Save should be disabled
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(called, isFalse);
      // Dialog should still be open
      expect(find.text('Rename Thread'), findsOneWidget);
    });

    testWidgets('submitted name is trimmed', (tester) async {
      String? submittedName;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => TextButton(
                    onPressed:
                        () => showDialog<void>(
                          context: context,
                          builder:
                              (_) => RenameDialog(
                                initialName: 'Original',
                                onAction: (name) async => submittedName = name,
                              ),
                        ),
                    child: const Text('Open'),
                  ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '  New Name  ');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(submittedName, 'New Name');
    });
  });
}
