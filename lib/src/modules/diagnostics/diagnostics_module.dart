import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_module.dart';
import '../../core/routes.dart';
import 'diagnostics_providers.dart';
import 'network_inspector.dart';
import 'ui/diagnostics_screen.dart';

class DiagnosticsAppModule extends AppModule {
  DiagnosticsAppModule({
    required this.appName,
    required this.inspector,
    this.logo,
  });

  final String appName;
  final Widget? logo;
  final NetworkInspector inspector;

  @override
  String get namespace => 'diagnostics';

  @override
  ModuleRoutes build() => ModuleRoutes(
        // A user who cannot sign in is unauthenticated by definition, and this
        // screen is where the failure is visible. Guarding it would put the
        // diagnosis out of reach of exactly the session that needs it.
        //
        // What that exposes without a session: request metadata, already
        // redacted at capture (HttpRedactor replaces the values of
        // Authorization, cookies and token-bearing query parameters), and log
        // records, which are not redacted by anything.
        // Those carry server and discovery URLs, hostnames and token expiry
        // times — deployment detail, not credentials — and the release level
        // floor keeps them to warnings and above. Nothing enforces that, so a
        // logger that starts recording a secret makes it readable here.
        publicPaths: const {AppRoutes.diagnostics},
        overrides: [
          networkInspectorProvider.overrideWithValue(inspector),
        ],
        routes: [
          GoRoute(
            path: AppRoutes.diagnostics,
            builder: (context, state) => DiagnosticsScreen(
              appName: appName,
              logo: logo,
              initialRunId: state.uri.queryParameters['run'],
              inspector: inspector,
            ),
          ),
        ],
      );

  @override
  Future<void> onDispose() async => inspector.dispose();
}
