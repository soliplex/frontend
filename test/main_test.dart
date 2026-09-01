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
  testWidgets(
      'a failed build reaches the screen instead of stalling the launch',
      (tester) async {
    // Without this the throw lands before any view is attached: no crash, no
    // report, and a launch that simply never finishes on iOS, macOS and
    // Android. The rethrow keeps the engine's own report intact.
    await expectLater(
      runSoliplexShell(
        () => throw ArgumentError('Public path "/welcom" is declared by'),
      ),
      throwsA(isA<ArgumentError>()),
    );
    await tester.pump();

    expect(find.text('This build could not start'), findsOneWidget);
    expect(find.textContaining('/welcom'), findsOneWidget);
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
