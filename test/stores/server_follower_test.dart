import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/stores/server_follower.dart';

import '../helpers/test_server_entry.dart';

const _a = 'http://a:8000';
const _b = 'http://b:8000';

ServerEntry _entry(String id) => createTestServerEntry(
      serverId: id,
      alias: id,
      requiresAuth: true,
      auth: authInActiveSession(),
    );

void _signIn(AuthSession auth) => auth.login(
      provider: const OidcProvider(
        discoveryUrl: 'https://idp.test/.well-known/openid-configuration',
        clientId: 'client',
      ),
      tokens: AuthTokens(
        accessToken: 'access',
        refreshToken: 'refresh',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );

/// A follower over two signed-in servers, recording what it reports.
({
  Signal<String?> selection,
  Signal<Map<String, ServerEntry>> servers,
  List<String> events,
  ServerFollower follower,
}) _harness({String? selected}) {
  final selection = Signal<String?>(selected);
  final servers = Signal<Map<String, ServerEntry>>({
    _a: _entry(_a),
    _b: _entry(_b),
  });
  final events = <String>[];
  final follower = ServerFollower(
    selection: selection,
    servers: servers,
    onServer: (entry) => events.add('server ${entry.serverId}'),
    onConnected: () => events.add('connected'),
    onDisconnected: ({required expired}) =>
        events.add(expired ? 'expired' : 'signed out'),
    onRemoved: () => events.add('removed'),
  );
  return (
    selection: selection,
    servers: servers,
    events: events,
    follower: follower,
  );
}

void main() {
  group('ServerFollower', () {
    test('reports the selected server, and each change of it', () {
      final h = _harness(selected: _a);
      h.selection.value = _b;
      h.selection.value = _b;

      expect(h.events, ['server $_a', 'server $_b']);
      h.follower.dispose();
    });

    test('ignores a null selection rather than reporting it', () {
      final h = _harness(selected: _a);
      h.selection.value = null;
      h.selection.value = _a;

      // Back on the server it never left: nothing to report.
      expect(h.events, ['server $_a']);
      h.follower.dispose();
    });

    test('waits for a selection the server list does not know yet', () {
      final h = _harness(selected: 'http://later:8000');
      expect(h.events, isEmpty);

      h.servers.value = {...h.servers.value, 'http://later:8000': _entry('x')};
      expect(h.events, ['server x']);
      h.follower.dispose();
    });

    test('reports the session ending and coming back', () {
      final h = _harness(selected: _a);
      final auth = h.servers.value[_a]!.auth;

      auth.markSessionExpired();
      auth.logout();
      _signIn(auth);

      // Expired then signed out is one disconnect: the server could not
      // serve requests either way.
      expect(h.events, ['server $_a', 'expired', 'connected']);
      h.follower.dispose();
    });

    test('a token refresh is not a reconnect', () {
      final h = _harness(selected: _a);
      _signIn(h.servers.value[_a]!.auth);

      expect(h.events, ['server $_a']);
      h.follower.dispose();
    });

    test('stops watching the old server once another is selected', () {
      final h = _harness(selected: _a);
      final oldAuth = h.servers.value[_a]!.auth;
      h.selection.value = _b;

      oldAuth.logout();

      expect(h.events, ['server $_a', 'server $_b']);
      h.follower.dispose();
    });

    test('reports the followed server being removed', () {
      final h = _harness(selected: _a);
      h.servers.value = {_b: h.servers.value[_b]!};

      expect(h.events, ['server $_a', 'removed']);
      h.follower.dispose();
    });

    test('reports nothing after dispose', () {
      final h = _harness(selected: _a);
      final auth = h.servers.value[_a]!.auth;
      h.follower.dispose();

      h.selection.value = _b;
      auth.logout();

      expect(h.events, ['server $_a']);
    });
  });
}
