import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart' show SoliplexTheme;
import 'package:soliplex_frontend/soliplex_frontend.dart';

void main() {
  AppIdentity identity() =>
      AppIdentity(appName: 'Test', logoLight: const SizedBox());

  group('Flavor.build', () {
    test('threads every declaration field into the ShellConfig', () async {
      final light = buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      );
      final dark = buildSoliplexThemeData(
        colors: darkSoliplexColors,
        brightness: Brightness.dark,
      );
      final refresh = ValueNotifier(0);
      addTearDown(refresh.dispose);

      final config = await Flavor(
        identity: identity(),
        theme: FlavorTheme.themeData(
          light: light,
          dark: dark,
          mode: ThemeMode.dark,
        ),
        modules: const [],
        initialRoute: '/somewhere',
        refreshListenable: refresh,
        inactivity: InactivityConfig.disabled,
      ).build();

      expect(config.appName, 'Test');
      expect(config.lightTheme, same(light));
      expect(config.darkTheme, same(dark));
      expect(config.themeMode, ThemeMode.dark);
      expect(config.initialRoute, '/somewhere');
      expect(config.refreshListenable, same(refresh));
      expect(config.inactivity, InactivityConfig.disabled);
    });

    test('lowers a BrandTheme once per brightness at build time', () async {
      final config = await Flavor(
        identity: identity(),
        theme: const FlavorTheme.brand(BrandTheme.soliplex()),
        modules: const [],
      ).build();

      // Lowered themes carry the extension, so the fromModules guard passes
      // and both brightnesses came through the same lowering.
      expect(config.lightTheme.extension<SoliplexTheme>(), isNotNull);
      expect(config.darkTheme!.extension<SoliplexTheme>(), isNotNull);
      expect(config.themeMode, ThemeMode.system);
    });
  });

  group('Flavor.copyWith', () {
    test('derives a variant without disturbing unrelated fields', () {
      final base = Flavor(
        identity: identity(),
        theme: const FlavorTheme.brand(BrandTheme.soliplex()),
        modules: const [],
        initialRoute: '/base',
      );

      final light = buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      );
      final variant = base.copyWith(theme: FlavorTheme.themeData(light: light));

      expect(variant.theme.brand, isNull);
      expect(variant.initialRoute, '/base');
      expect(variant.identity, same(base.identity));
      expect(variant.modules, same(base.modules));
    });
  });
}
