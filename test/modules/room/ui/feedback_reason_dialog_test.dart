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

const _unreadableNote = "Couldn't check for an earlier note. "
    'Submitting replaces any that exists.';

void main() {
  testWidgets('renders the prompt, the hint and both actions', (tester) async {
    await _open(tester);

    expect(find.text('Tell us why'), findsOneWidget);
    expect(find.text('Add a reason (optional)'), findsOneWidget);
    expect(find.text('Close'), findsOneWidget);
    expect(find.text('Send'), findsOneWidget);
  });

  group('width', () {
    // The field states no intrinsic width preference, so without a width the
    // dialog sits at Material's 280 minimum however wide the window is.
    testWidgets('uses the dialog width on a wide window', (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _open(tester);

      expect(tester.getSize(find.byType(TextField)).width, greaterThan(400));
    });

    testWidgets('stays inside a narrow window', (tester) async {
      // A fixed width must still yield to the incoming constraints, or the
      // dialog overflows the screen on a phone.
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await _open(tester);

      expect(tester.getSize(find.byType(TextField)).width, lessThan(360));
      expect(tester.takeException(), isNull);
    });
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
    await tester.tap(find.text('Close'));
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

    testWidgets('puts the cursor in the field once the note is loaded',
        (tester) async {
      // The field is disabled while loading, so autofocus is dropped and the
      // node refuses focus until the rebuild re-enables it. Without a cursor
      // the user has to tap before they can extend the note, which is the
      // whole point of this entry point.
      await _open(tester, loadInitialText: () async => 'on file');

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.focusNode?.hasFocus, isTrue);
    });

    testWidgets('says so when it could not be read, and still submits',
        (tester) async {
      // Never claims nothing is on file: an unreadable note is not an absent
      // one, and submitting replaces whatever is there.
      final submitted = await _open(
        tester,
        loadInitialText: () async => throw Exception('offline'),
      );

      expect(find.text(_unreadableNote), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'still worth saying');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(submitted, ['still worth saying']);
    });

    testWidgets('shows the warning outside the input, uncapped',
        (tester) async {
      // As the input's helperText the warning is clamped to two lines and
      // ellipsized, which drops the clause naming what a submit replaces —
      // and the error text displaces it entirely. Neither is survivable in a
      // slot the input owns.
      await _open(
        tester,
        loadInitialText: () async => throw Exception('offline'),
      );

      expect(
        find.descendant(
          of: find.byType(TextField),
          matching: find.text(_unreadableNote),
        ),
        findsNothing,
      );
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

    testWidgets('keeps the unreadable-note warning through a failed send',
        (tester) async {
      // A failed send is when the user is most likely to press Send again, so
      // it is exactly when the warning that a submit replaces whatever is on
      // file matters most. The error must not take its place.
      await _open(
        tester,
        loadInitialText: () async => throw Exception('offline'),
        onSubmit: (_) async => false,
      );

      await tester.enterText(find.byType(TextField), 'worth keeping');
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();

      expect(find.text('Couldn\'t send that. Try again.'), findsOneWidget);
      expect(find.text(_unreadableNote), findsOneWidget);
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

    testWidgets('stays escapable while the send is in flight', (tester) async {
      // The barrier is not dismissible and the request has no deadline short
      // enough to wait out, so a disabled Cancel would be the only way out of
      // a hung send — on iOS there is no back button to fall back on.
      final gate = Completer<bool>();
      await _open(tester, onSubmit: (_) => gate.future);

      await tester.enterText(find.byType(TextField), 'worth keeping');
      await tester.tap(find.text('Send'));
      await tester.pump();

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      expect(find.text('Tell us why'), findsNothing);
      gate.complete(true);
      await tester.pumpAndSettle();
    });

    testWidgets('closes even when a route covered it mid-send', (tester) async {
      // A route pushed over the dialog (the inactivity warning does this on a
      // timer) means the send resolves while this is not the current route.
      // Without releasing the flag the dialog is left with every control
      // disabled once that route goes.
      final gate = Completer<bool>();
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                barrierDismissible: false,
                builder: (_) => FeedbackReasonDialog(
                  onSubmit: (_) => gate.future,
                ),
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'covered');
      await tester.tap(find.text('Send'));
      await tester.pump();

      navigatorKey.currentState!.push(
        DialogRoute<void>(
          context: navigatorKey.currentContext!,
          builder: (_) => const AlertDialog(title: Text('On top')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      gate.complete(true);
      await tester.pump();

      navigatorKey.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Gone, not left looking unsent: the note is on file, so a dialog still
      // showing the typed text would invite the user to conclude it never went.
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
