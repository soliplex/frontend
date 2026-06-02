import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/shared/marking/pre_access_notice.dart';

class _HomeModule extends AppModule {
  @override
  String get namespace => 'home';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [
          GoRoute(path: '/', builder: (_, __) => const Text('Soliplex')),
        ],
        // Pre-acknowledge the marking notice so the home route shows
        // directly rather than the pre-access gate.
        overrides: [
          markingNoticeAcknowledgedProvider
              .overrideWithValue(Signal<bool>(true)),
        ],
      );
}

void main() {
  testWidgets('app boots and renders home screen', (tester) async {
    final config = await ShellConfig.fromModules(
      appName: 'Soliplex',
      lightTheme: ThemeData(),
      modules: [_HomeModule()],
    );
    runSoliplexShell(config);
    await tester.pumpAndSettle();
    expect(find.text('Soliplex'), findsOneWidget);
  });
}
