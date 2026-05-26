import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_design_example/main.dart';

Widget _gallery({required Brightness brightness}) {
  return MaterialApp(
    theme: brightness == Brightness.light
        ? soliplexLightTheme()
        : soliplexDarkTheme(),
    home: const Scaffold(
      body: SingleChildScrollView(
        padding: EdgeInsets.all(SoliplexSpacing.s4),
        child: InputGallery(),
      ),
    ),
  );
}

void main() {
  testWidgets('InputGallery — light', (tester) async {
    tester.view.physicalSize = const Size(700, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_gallery(brightness: Brightness.light));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/input_gallery_light.png'),
    );
  });

  testWidgets('InputGallery — dark', (tester) async {
    tester.view.physicalSize = const Size(700, 1900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_gallery(brightness: Brightness.dark));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/input_gallery_dark.png'),
    );
  });
}
