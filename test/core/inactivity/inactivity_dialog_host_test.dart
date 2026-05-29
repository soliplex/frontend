import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show Signal;
import 'package:soliplex_frontend/src/core/inactivity/inactivity_config.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_dialog.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_dialog_host.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_monitor.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

import '../../helpers/test_server_entry.dart';

const _provider = OidcProvider(
  discoveryUrl: 'https://idp.example.com/.well-known/openid-configuration',
  clientId: 'test-client',
);

AuthTokens _tokens() => AuthTokens(
      accessToken: 'a',
      refreshToken: 'r',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

void main() {
  testWidgets(
    'pushes the dialog when the warning fires and removes it on extend',
    (tester) async {
      final servers = Signal<Map<String, ServerEntry>>({});
      // Short warning so a pump can fire it; long grace so the logout
      // timer doesn't fire mid-test.
      final monitor = InactivityMonitor(
        servers: servers,
        config: const InactivityConfig(
          warningDuration: Duration(seconds: 1),
          graceDuration: Duration(minutes: 5),
        ),
      );

      final entry = createTestServerEntry(serverId: 'server-1')
        ..auth.login(provider: _provider, tokens: _tokens());
      servers.value = {entry.serverId: entry};

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navKey,
        home: InactivityDialogHost(
          monitor: monitor,
          navigatorKey: navKey,
          child: const Scaffold(body: Center(child: Text('content'))),
        ),
      ));

      // Nothing before the idle window elapses.
      expect(find.byType(InactivityDialog), findsNothing);

      await tester.pump(const Duration(seconds: 1)); // warning timer fires
      await tester.pump(); // host's deferred microtask pushes the dialog
      expect(find.byType(InactivityDialog), findsOneWidget);

      // "Stay signed in" clears warningVisible; the host removes the route.
      monitor.extendSession();
      await tester.pump(); // host's deferred microtask calls removeRoute
      await tester.pump(); // navigator rebuilds without the dialog
      expect(find.byType(InactivityDialog), findsNothing);

      // Cancel the re-armed warning timer before end-of-test invariants.
      monitor.dispose();
    },
  );
}
