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
  });
}
