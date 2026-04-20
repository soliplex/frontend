import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/scroll/scroll_to_bottom.dart';

void main() {
  group('ScrollToBottomController', () {
    late ScrollToBottomController controller;

    setUp(() {
      controller = ScrollToBottomController();
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts not visible', () {
      expect(controller.visible, isFalse);
    });

    test('scheduleAppearance makes visible after 300ms delay', () {
      fakeAsync((async) {
        controller.scheduleAppearance();

        async.elapse(const Duration(milliseconds: 299));
        expect(controller.visible, isFalse);

        async.elapse(const Duration(milliseconds: 1));
        expect(controller.visible, isTrue);
      });
    });

    test('hide() cancels pending appearance and stays hidden', () {
      fakeAsync((async) {
        controller.scheduleAppearance();

        async.elapse(const Duration(milliseconds: 150));
        controller.hide();

        async.elapse(const Duration(milliseconds: 200));
        expect(controller.visible, isFalse);
      });
    });

    test('hide() hides immediately when already visible', () {
      fakeAsync((async) {
        controller.scheduleAppearance();
        async.elapse(const Duration(milliseconds: 300));
        expect(controller.visible, isTrue);

        controller.hide();
        expect(controller.visible, isFalse);
      });
    });

    test('auto-hides after 3 seconds of inactivity', () {
      fakeAsync((async) {
        controller.scheduleAppearance();
        async.elapse(const Duration(milliseconds: 300));
        expect(controller.visible, isTrue);

        async.elapse(const Duration(seconds: 2, milliseconds: 999));
        expect(controller.visible, isTrue);

        async.elapse(const Duration(milliseconds: 1));
        expect(controller.visible, isFalse);
      });
    });

    test(
      'scheduleAppearance is idempotent — second call does not reset timer',
      () {
        fakeAsync((async) {
          controller.scheduleAppearance();
          async.elapse(const Duration(milliseconds: 200));

          // Second call should be a no-op; timer keeps running from original start.
          controller.scheduleAppearance();
          async.elapse(const Duration(milliseconds: 100));

          // 300ms total elapsed since first call — should be visible now.
          expect(controller.visible, isTrue);
        });
      },
    );

    test('notifies listeners when visibility changes', () {
      fakeAsync((async) {
        int notifyCount = 0;
        controller.addListener(() => notifyCount++);

        controller.scheduleAppearance();
        async.elapse(const Duration(milliseconds: 300));
        expect(notifyCount, 1); // appeared

        async.elapse(const Duration(seconds: 3));
        expect(notifyCount, 2); // auto-hidden
      });
    });

    test('dispose cancels pending timers without notifying', () {
      // Use a fresh controller so tearDown doesn't double-dispose.
      final local = ScrollToBottomController();
      fakeAsync((async) {
        local.scheduleAppearance();

        // Should not throw when dispose fires while timer is pending.
        local.dispose();

        // Elapsing time after dispose should not trigger visibility changes
        // (timers were cancelled).
        expect(() => async.elapse(const Duration(seconds: 5)), returnsNormally);
      });
    });
  });

  group('ScrollToBottomButton', () {
    testWidgets('renders FAB when controller is visible', (tester) async {
      final controller = ScrollToBottomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ScrollToBottomButton(controller: controller)),
        ),
      );

      expect(find.byType(FloatingActionButton), findsOneWidget);
    });

    testWidgets('calls onPressed when tapped while visible', (tester) async {
      bool pressed = false;
      final controller = ScrollToBottomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScrollToBottomButton(
                controller: controller,
                onPressed: () => pressed = true,
              ),
            ),
          ),
        ),
      );

      // Make the button visible.
      fakeAsync((async) {
        controller.scheduleAppearance();
        async.elapse(const Duration(milliseconds: 300));
      });
      await tester.pump();

      await tester.tap(find.byType(FloatingActionButton));
      expect(pressed, isTrue);
    });

    testWidgets('FAB is pointer-ignored when not visible', (tester) async {
      bool pressed = false;
      final controller = ScrollToBottomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: ScrollToBottomButton(
                controller: controller,
                onPressed: () => pressed = true,
              ),
            ),
          ),
        ),
      );

      // controller.visible is false — tapping should be ignored.
      await tester.tap(find.byType(FloatingActionButton), warnIfMissed: false);
      expect(pressed, isFalse);
    });

    testWidgets('opacity is 0 when not visible and 1 when visible', (
      tester,
    ) async {
      final controller = ScrollToBottomController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: ScrollToBottomButton(controller: controller)),
          ),
        ),
      );

      AnimatedOpacity opacityWidget() =>
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));

      expect(opacityWidget().opacity, 0.0);

      fakeAsync((async) {
        controller.scheduleAppearance();
        async.elapse(const Duration(milliseconds: 300));
      });
      await tester.pump();

      expect(opacityWidget().opacity, 1.0);
    });
  });
}
