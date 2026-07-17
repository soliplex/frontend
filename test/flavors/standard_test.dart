import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

import 'platform_mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installPlatformMocks();

  test('threads themeMode and classifications into the lowered config',
      () async {
    // Every parameter mapped in standard() has a default, so a dropped
    // forwarding compiles clean; non-default values make it observable.
    final classifications = ClassificationTheme(
      defaultId: 'low',
      levels: const [
        ClassificationLevel(
          id: 'low',
          label: 'LOW',
          background: Color(0xFF111111),
          foreground: Color(0xFFFFFFFF),
        ),
      ],
    );

    final config = await standard(
      themeMode: ThemeMode.dark,
      classifications: classifications,
    );
    addTearDown(config.dispose);

    expect(config.themeMode, ThemeMode.dark);
    expect(
      config.lightTheme.extension<ClassificationTheme>(),
      same(classifications),
    );
    expect(
      config.darkTheme!.extension<ClassificationTheme>(),
      same(classifications),
    );
  });
}
