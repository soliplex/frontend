import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_design/soliplex_design.dart';

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
  testWidgets('app boots and renders home screen', (tester) async {
    final config = await ShellConfig.fromModules(
      appName: 'Soliplex',
      lightTheme: buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      ),
      modules: [_HomeModule()],
    );
    runSoliplexShell(config);
    await tester.pumpAndSettle();
    expect(find.text('Soliplex'), findsOneWidget);
  });
}
