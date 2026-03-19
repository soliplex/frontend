import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_frontend/soliplex_frontend.dart';

void main() {
  testWidgets('app boots and renders home screen', (tester) async {
    final config = ShellConfig(
      appName: 'Soliplex',
      theme: ThemeData(),
      modules: [
        ModuleContribution(
          routes: [
            GoRoute(path: '/', builder: (_, __) => const Text('Soliplex')),
          ],
        ),
      ],
    );
    runSoliplexShell(config);
    await tester.pumpAndSettle();
    expect(find.text('Soliplex'), findsOneWidget);
  });
}
