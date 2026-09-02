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
        // A user who cannot sign in is unauthenticated by definition, and
        // this screen is where the failure is visible. Guarding it would put
        // the diagnosis out of reach of exactly the session that needs it.
        //
        // What that opens without a session is more than request metadata:
        // request and response bodies, SSE payloads, copy-as-curl with
        // headers, and a file export of the whole capture including log
        // records. HttpRedactor works from known names, so redaction at
        // capture covers what it recognises and no more, and log records are
        // not redacted at all. docs/diagnostics-known-risks.md carries the
        // standing analysis; this comment records only the decision.
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
