import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_dialog.dart';

Widget _hostDialog({
  required ReadonlySignal<DateTime?> graceDeadline,
  required VoidCallback onExtend,
  required VoidCallback onLogout,
}) {
  return MaterialApp(
    home: Scaffold(
      body: InactivityDialog(
        graceDeadline: graceDeadline,
        onExtend: onExtend,
        onLogout: onLogout,
      ),
    ),
  );
}

void main() {
  group('InactivityDialog', () {
    testWidgets('tapping "Stay signed in" invokes onExtend', (tester) async {
      var extendCount = 0;
      final start = DateTime(2026);
      final deadline = Signal<DateTime?>(start.add(const Duration(minutes: 5)));

      await withClock(Clock.fixed(start), () async {
        await tester.pumpWidget(_hostDialog(
          graceDeadline: deadline,
          onExtend: () => extendCount++,
          onLogout: () {},
        ));

        await tester.tap(find.text('Stay signed in'));
        await tester.pump();
      });

      expect(extendCount, 1);
    });

    testWidgets('tapping "Sign out now" invokes onLogout', (tester) async {
      var logoutCount = 0;
      final start = DateTime(2026);
      final deadline = Signal<DateTime?>(start.add(const Duration(minutes: 5)));

      await withClock(Clock.fixed(start), () async {
        await tester.pumpWidget(_hostDialog(
          graceDeadline: deadline,
          onExtend: () {},
          onLogout: () => logoutCount++,
        ));

        await tester.tap(find.text('Sign out now'));
        await tester.pump();
      });

      expect(logoutCount, 1);
    });

    testWidgets('displays remaining time in mm:ss format', (tester) async {
      final start = DateTime(2026);
      final deadline = Signal<DateTime?>(
        start.add(const Duration(minutes: 4, seconds: 7)),
      );

      await withClock(Clock.fixed(start), () async {
        await tester.pumpWidget(_hostDialog(
          graceDeadline: deadline,
          onExtend: () {},
          onLogout: () {},
        ));

        expect(find.text('04:07'), findsOneWidget);
      });
    });

    testWidgets('countdown updates when one second elapses', (tester) async {
      final start = DateTime(2026);
      var now = start;
      final deadline = Signal<DateTime?>(start.add(const Duration(minutes: 5)));

      await withClock(Clock(() => now), () async {
        await tester.pumpWidget(_hostDialog(
          graceDeadline: deadline,
          onExtend: () {},
          onLogout: () {},
        ));

        expect(find.text('05:00'), findsOneWidget);

        now = start.add(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));

        expect(find.text('04:59'), findsOneWidget);
      });
    });

    testWidgets('clamps to 00:00 when the deadline has passed', (tester) async {
      final start = DateTime(2026);
      final deadline =
          Signal<DateTime?>(start.subtract(const Duration(seconds: 30)));

      await withClock(Clock.fixed(start), () async {
        await tester.pumpWidget(_hostDialog(
          graceDeadline: deadline,
          onExtend: () {},
          onLogout: () {},
        ));

        expect(find.text('00:00'), findsOneWidget);
      });
    });
  });
}
