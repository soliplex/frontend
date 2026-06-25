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
        child: DropdownGallery(),
      ),
    ),
  );
}

void main() {
  testWidgets('DropdownGallery — light', (tester) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_gallery(brightness: Brightness.light));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dropdown_gallery_light.png'),
    );
  });

  testWidgets('DropdownGallery — dark', (tester) async {
    tester.view.physicalSize = const Size(700, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_gallery(brightness: Brightness.dark));
    await tester.pump();

    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/dropdown_gallery_dark.png'),
    );
  });
}
