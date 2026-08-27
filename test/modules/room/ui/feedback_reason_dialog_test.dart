import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/feedback_reason_dialog.dart';

/// Opens the dialog over a trivial host and returns the reasons [onSubmit]
/// received, so assertions read the text the dialog actually submitted rather
/// than the controller it holds.
Future<List<String>> _open(
  WidgetTester tester, {
  Future<bool> Function(String reason)? onSubmit,
  Future<String?> Function()? loadInitialText,
}) async {
  final submitted = <String>[];
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => FeedbackReasonDialog(
                loadInitialText: loadInitialText,
                onSubmit: (reason) async {
                  submitted.add(reason);
                  return onSubmit == null ? true : await onSubmit(reason);
                },
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
  return submitted;
}

void main() {
  testWidgets('renders the prompt, the hint and both actions', (tester) async {
    await _open(tester);

    expect(find.text('Tell us why'), findsOneWidget);
    expect(find.text('Add a reason (optional)'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });

  testWidgets('Send submits the typed text and closes', (tester) async {
    final submitted = await _open(tester);

    await tester.enterText(find.byType(TextField), 'Bad citation');
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();

    expect(submitted, ['Bad citation']);
    expect(find.text('Tell us why'), findsNothing);
  });

  testWidgets('Cancel submits nothing and closes', (tester) async {
    final submitted = await _open(tester);

    await tester.enterText(find.byType(TextField), 'never mind');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(submitted, isEmpty);
    expect(find.text('Tell us why'), findsNothing);
  });

  group('the note already on file', () {
    testWidgets('withholds Send until the note has been read', (tester) async {
      // Submitting mid-load would upsert over a note nobody has seen yet.
      final gate = Completer<String?>();
      final submitted = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackReasonDialog(
              loadInitialText: () => gate.future,
              onSubmit: (reason) async {
                submitted.add(reason);
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.text('Send'), warnIfMissed: false);
      await tester.pump();
      expect(submitted, isEmpty);

      gate.complete('on file');
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(submitted, ['on file']);
    });

    testWidgets('says so when it could not be read, and still submits',
        (tester) async {
      // Never claims nothing is on file: an unreadable note is not an absent
      // one, and submitting replaces whatever is there.
      final submitted = await _open(
        tester,
        loadInitialText: () async => throw Exception('offline'),
      );

      expect(
        find.text(
          'Couldn\'t check for an earlier note. '
          'Submitting replaces any that exists.',
        ),
        findsOneWidget,
      );

      await tester.enterText(find.byType(TextField), 'still worth saying');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submitted, ['still worth saying']);
    });
  });

  group('submitting', () {
    testWidgets('stays open with the text intact when the send fails',
        (tester) async {
      await _open(tester, onSubmit: (_) async => false);

      await tester.enterText(find.byType(TextField), 'worth keeping');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(find.text('Tell us why'), findsOneWidget);
      expect(find.text('worth keeping'), findsOneWidget);
      expect(find.text('Couldn\'t send that. Try again.'), findsOneWidget);
    });

    testWidgets('a retry after a failure can succeed', (tester) async {
      var attempts = 0;
      final submitted = await _open(
        tester,
        onSubmit: (_) async => ++attempts > 1,
      );

      await tester.enterText(find.byType(TextField), 'worth keeping');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submitted, ['worth keeping', 'worth keeping']);
      expect(find.text('Tell us why'), findsNothing);
    });

    testWidgets('ignores a second tap while the first is in flight',
        (tester) async {
      final gate = Completer<bool>();
      final submitted = await _open(tester, onSubmit: (_) => gate.future);

      await tester.enterText(find.byType(TextField), 'once');
      await tester.tap(find.text('Send'));
      await tester.pump();
      await tester.tap(find.text('Send'), warnIfMissed: false);
      await tester.pump();

      expect(submitted, ['once']);

      gate.complete(true);
      await tester.pumpAndSettle();
    });
  });
}
