import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/scroll/anchored_scroll_controller.dart';

void main() {
  group('AnchoredScrollController', () {
    Widget buildListView(AnchoredScrollController controller) {
      return MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              for (var i = 0; i < 100; i++) const SizedBox(height: 50)
            ],
          ),
        ),
      );
    }

    testWidgets('setAnchor expands maxScrollExtent beyond natural content',
        (tester) async {
      final controller = AnchoredScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildListView(controller));

      final naturalMax = controller.position.maxScrollExtent;
      final anchorOffset = naturalMax + 500;

      controller.setAnchor(anchorOffset);
      // jumpTo to a different pixel value triggers notifyListeners on the
      // ViewportOffset, which causes the viewport to markNeedsLayout and
      // re-run applyContentDimensions with the new anchor.
      controller.jumpTo(1.0);
      await tester.pump();

      expect(controller.position.maxScrollExtent, anchorOffset);
    });

    testWidgets('clearAnchor reverts to natural scroll bounds', (tester) async {
      final controller = AnchoredScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildListView(controller));

      final naturalMax = controller.position.maxScrollExtent;

      controller.setAnchor(naturalMax + 500);
      controller.jumpTo(1.0);
      await tester.pump();

      controller.clearAnchor();
      controller.jumpTo(0.0);
      await tester.pump();

      expect(controller.position.maxScrollExtent, naturalMax);
    });

    testWidgets(
        'maxScrollExtent is the max of natural extent and anchor offset',
        (tester) async {
      final controller = AnchoredScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(buildListView(controller));

      final naturalMax = controller.position.maxScrollExtent;

      // Anchor below natural max — natural max wins.
      controller.setAnchor(naturalMax - 100);
      controller.jumpTo(1.0);
      await tester.pump();

      expect(controller.position.maxScrollExtent, naturalMax);

      // Anchor above natural max — anchor wins.
      controller.setAnchor(naturalMax + 200);
      controller.jumpTo(0.0);
      await tester.pump();

      expect(controller.position.maxScrollExtent, naturalMax + 200);
    });

    testWidgets('keeps the anchor when the scroll position is replaced',
        (tester) async {
      // The Scrollable builds a new position whenever a dependency it reads
      // changes, such as the theme when the OS switches light and dark.
      final controller = AnchoredScrollController();
      addTearDown(controller.dispose);
      Widget list(Brightness brightness) => MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: Scaffold(
              body: ListView(
                controller: controller,
                children: [
                  for (var i = 0; i < 100; i++) const SizedBox(height: 50)
                ],
              ),
            ),
          );

      await tester.pumpWidget(list(Brightness.light));
      final anchorOffset = controller.position.maxScrollExtent + 500;
      controller.setAnchor(anchorOffset);
      controller.jumpTo(anchorOffset);
      await tester.pump();
      final original = controller.position;

      await tester.pumpWidget(list(Brightness.dark));
      await tester.pumpAndSettle();

      expect(controller.position, isNot(same(original)),
          reason: 'the theme change replaced the scroll position');
      expect(controller.anchorOffset, anchorOffset);
      expect(controller.position.pixels, anchorOffset);
    });
  });
}
