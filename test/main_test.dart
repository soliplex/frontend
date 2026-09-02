import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';

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

  testWidgets('a rejected configuration reaches the screen whole',
      (tester) async {
    // Driven through a real rejection rather than a synthetic throw, so this
    // also pins that the abort paths use the type the screen renders whole. A
    // path that reverts to a plain ArgumentError is reduced by describeFailure
    // to seven words and this goes red.
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
