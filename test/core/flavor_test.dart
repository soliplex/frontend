import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart' show SoliplexTheme;
import 'package:soliplex_frontend/soliplex_frontend.dart';

import 'route_module.dart';

void main() {
  AppIdentity identity() =>
      AppIdentity(appName: 'Test', logoLight: const SizedBox());

  group('Flavor.build', () {
    test('threads every declaration field into the ShellConfig', () {
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

      final config = Flavor(
        identity: identity(),
        theme: FlavorTheme.themeData(
          light: light,
          dark: dark,
          mode: ThemeMode.dark,
        ),
        modules: [
          RouteModule(const ['/somewhere'])
        ],
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

    test('brand path lowers both brightnesses through the same pipeline', () {
      final config = Flavor(
        identity: identity(),
        theme: const FlavorTheme.brand(BrandTheme.soliplex()),
        modules: [
          RouteModule(const ['/'])
        ],
      ).build();

      // Lowered themes carry the extension, so the fromModules guard passes
      // and both brightnesses came through the same lowering.
      expect(config.lightTheme.extension<SoliplexTheme>(), isNotNull);
      expect(config.darkTheme!.extension<SoliplexTheme>(), isNotNull);
      expect(config.themeMode, ThemeMode.system);
    });

    test('rejects a bare ThemeData that lacks the SoliplexTheme extension', () {
      final flavor = Flavor(
        identity: identity(),
        theme: FlavorTheme.themeData(light: ThemeData()),
        modules: [
          RouteModule(const ['/'])
        ],
      );

      expect(flavor.build, throwsArgumentError);
    });

    test('throws on a second build so live modules are never re-consumed', () {
      final flavor = Flavor(
        identity: identity(),
        theme: const FlavorTheme.brand(BrandTheme.soliplex()),
        modules: [
          RouteModule(const ['/'])
        ],
      );

      flavor.build();
      expect(flavor.build, throwsStateError);
    });

    test('a theme that fails to resolve leaves the flavor buildable', () {
      // Only the modules are single-use, and lowering happens before any is
      // touched. Spending the flavor on a fork-supplied FontResolver's throw
      // would replace that resolver's message — the one naming the fault —
      // with 'already called' on every retry, including the boot screen's.
      final flavor = Flavor(
        identity: identity(),
        theme: FlavorTheme.brand(
          BrandTheme.fromSeed(
            const Color(0xFF336699),
            // Without a family set, nothing calls the resolver and this test
            // would pass on a flavor that never resolved a font at all.
            typography: const BrandTypography(brandFamily: 'Nonesuch'),
          ),
          fontResolver: const _ThrowingFontResolver(),
        ),
        modules: [
          RouteModule(const ['/'])
        ],
      );

      for (final attempt in ['first', 'second']) {
        expect(
          flavor.build,
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('font unavailable'),
            ),
          ),
          reason: 'the $attempt build reports the resolver, not "already '
              'called"',
        );
      }
    });
  });
}

class _ThrowingFontResolver extends FontResolver {
  const _ThrowingFontResolver();

  @override
  ResolvedFont resolve(String family, List<String> fallbacks) =>
      throw StateError('font unavailable');
}
