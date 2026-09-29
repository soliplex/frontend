import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/thread_state_warning_banner.dart';

void main() {
  testWidgets(
      'every warning at once leaves the timeline room on a short screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 250);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // Laid out as the room screen lays it out: below the timeline.
    await tester.pumpWidget(
      MaterialApp(
        theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox.expand(key: Key('timeline'))),
              ThreadStateWarningBanner(
                warnings: ThreadStateWarning.values.toSet(),
                onDismiss: () {},
              ),
            ],
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const Key('timeline'))).height,
      greaterThan(0),
    );
    expect(find.byTooltip('Dismiss'), findsOneWidget);
  });
}
