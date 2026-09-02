import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';

ThemeData _themed() => buildSoliplexThemeData(
      colors: lightSoliplexColors,
      brightness: Brightness.light,
    );

class _HomeModule extends AppModule {
  @override
  String get namespace => 'home';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('Soliplex')),
        ],
      );
}

/// Declares a public path one character off the route it registers — the
/// mistake a fork makes, and the one whose whole diagnosis is the path itself.
class _PublicPathTypoModule extends AppModule {
  @override
  String get namespace => 'welcome';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('Soliplex')),
          GoRoute(path: '/welcome', builder: (_, __) => const Text('Welcome')),
        ],
        publicPaths: const {'/welcom'},
      );
}

void main() {
  testWidgets('a failure that is not ours shows its type, not its contents',
      (tester) async {
    // The catch takes anything the flavor's async assembly can throw, and
    // SharedPreferences.getInstance() sits outside a try in two places on that
    // path. A FormatException carries a window of the value it failed on, and
    // this screen is more exposed than the diagnostics buffer: no navigation,
    // no export, and deliberately copyable.
    await expectLater(
      runSoliplexShell(
        () => throw const FormatException('bad', 'SECRET-STORED-VALUE'),
      ),
      throwsA(isA<FormatException>()),
    );
    await tester.pump();

    expect(find.textContaining('SECRET-STORED-VALUE'), findsNothing);
    expect(find.textContaining('FormatException'), findsOneWidget);
  });

  // One per abort site, all four driven through a real rejection rather than a
  // synthetic throw, because the type is not exported: a test can only write
  // isA<ArgumentError>(), which a site reverting to a plain ArgumentError still
  // satisfies. Only the screen text tells the two apart — describeFailure
  // reduces a nameless ArgumentError to the one word 'ArgumentError', so
  // asserting the diagnosis reached the screen is what pins the site.
  testWidgets('a rejected lightTheme reaches the screen whole', (tester) async {
    await expectLater(
      runSoliplexShell(
        () => ShellConfig.fromModules(
          modules: [_HomeModule()],
          appName: 'Soliplex',
          lightTheme: ThemeData(), // bare: no SoliplexTheme extension
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await tester.pump();

    expect(find.text('This build could not start'), findsOneWidget);
    expect(find.textContaining('buildSoliplexThemeData'), findsOneWidget);
  });

  testWidgets('a rejected darkTheme reaches the screen whole', (tester) async {
    await expectLater(
      runSoliplexShell(
        () => ShellConfig.fromModules(
          modules: [_HomeModule()],
          appName: 'Soliplex',
          lightTheme: _themed(),
          darkTheme: ThemeData(), // bare: no SoliplexTheme extension
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await tester.pump();

    expect(find.textContaining('darkTheme'), findsOneWidget);
  });

  testWidgets('a rejected route configuration names the path on screen',
      (tester) async {
    // The case both ShellConfigurationError and runSoliplexShell lead with, and
    // the one where losing the text costs most: the offending path is the whole
    // diagnosis, and on a packaged build it exists nowhere else.
    await expectLater(
      runSoliplexShell(
        () => ShellConfig.fromModules(
          modules: [_PublicPathTypoModule()],
          appName: 'Soliplex',
          lightTheme: _themed(),
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await tester.pump();

    expect(find.textContaining('/welcom'), findsOneWidget);
  });

  testWidgets('a duplicated namespace reaches the screen whole',
      (tester) async {
    await expectLater(
      runSoliplexShell(
        () => ShellConfig.fromModules(
          modules: [_HomeModule(), _HomeModule()],
          appName: 'Soliplex',
          lightTheme: _themed(),
        ),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await tester.pump();

    expect(
        find.textContaining('Duplicate AppModule namespace'), findsOneWidget);
  });

  testWidgets('a flavor built twice says so on screen', (tester) async {
    // Not a _rejected site — Flavor.build throws its own StateError — so this
    // is what catches the boot surface learning to show only one of the two
    // diagnoses this package composes.
    final flavor = Flavor(
      identity: AppIdentity.soliplex,
      theme: FlavorTheme.themeData(light: _themed()),
      modules: [_HomeModule()],
    );
    flavor.build();

    await expectLater(
      runSoliplexShell(flavor.build),
      throwsA(isA<StateError>()),
    );
    await tester.pump();

    expect(find.textContaining('may be built only once'), findsOneWidget);
  });

  testWidgets('app boots and renders home screen', (tester) async {
    final config = ShellConfig.fromModules(
      appName: 'Soliplex',
      lightTheme: buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      ),
      modules: [_HomeModule()],
    );
    await runSoliplexShell(() => config);
    await tester.pumpAndSettle();
    expect(find.text('Soliplex'), findsOneWidget);
  });
}
