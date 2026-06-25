// Golden baseline is rendered on Linux (CI is the authority). On macOS these
// always show ~1% text-edge diffs from font rendering — that is NOT a
// regression. Never --update-goldens off Linux; skip locally with
// `flutter test --exclude-tags golden`.
@Tags(['golden'])
library;

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
        child: ChipGallery(),
      ),
    ),
  );
}

void main() {
  testWidgets('ChipGallery — light', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_gallery(brightness: Brightness.light));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chip_gallery_light.png'),
    );
  });

  testWidgets('ChipGallery — dark', (tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_gallery(brightness: Brightness.dark));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/chip_gallery_dark.png'),
    );
  });
}
