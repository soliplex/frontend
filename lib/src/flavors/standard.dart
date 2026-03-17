import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/shell_config.dart';
import '../interfaces/auth_state.dart';
import '../modules/auth/auth_module.dart';

ShellConfig standard() {
  return ShellConfig(
    appName: 'Soliplex',
    theme: ThemeData(),
    modules: [
      authModule(auth: Unauthenticated()),
      ModuleContribution(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, __) => const Scaffold(
              body: Center(child: Text('Soliplex')),
            ),
          ),
        ],
      ),
    ],
  );
}
