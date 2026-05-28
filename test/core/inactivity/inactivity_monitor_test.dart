import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_config.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_monitor.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';

import '../../helpers/fakes.dart';
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

ServerEntry _activeEntry({String id = 'server-1'}) {
  final entry = createTestServerEntry(serverId: id);
  entry.auth.login(provider: _provider, tokens: _tokens());
  return entry;
}

const _config = InactivityConfig(
  warningDuration: Duration(minutes: 10),
  graceDuration: Duration(minutes: 5),
);

void main() {
  group('InactivityMonitor', () {
    test('does not show the warning when no servers are active', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);

        async.elapse(const Duration(hours: 1));

        expect(monitor.warningVisible.value, isFalse);
        monitor.dispose();
      });
    });

    test('arms the warning timer when the first active session appears', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);

        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(minutes: 10) - const Duration(seconds: 1));
        expect(monitor.warningVisible.value, isFalse);

        async.elapse(const Duration(seconds: 1));
        expect(monitor.warningVisible.value, isTrue);

        monitor.dispose();
      });
    });

    test('bumpActivity restarts the warning timer', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(minutes: 9));
        monitor.bumpActivity();

        async.elapse(const Duration(minutes: 9));
        expect(monitor.warningVisible.value, isFalse);

        async.elapse(const Duration(minutes: 1));
        expect(monitor.warningVisible.value, isTrue);

        monitor.dispose();
      });
    });

    test('bumpActivity is a no-op while the warning dialog is open', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(minutes: 10));
        expect(monitor.warningVisible.value, isTrue);

        monitor.bumpActivity();
        async.elapse(const Duration(minutes: 1));
        monitor.bumpActivity();
        async.elapse(const Duration(minutes: 4));

        expect(entry.auth.session.value, isA<NoSession>());

        monitor.dispose();
      });
    });

    test('extendSession dismisses the dialog and restarts the warning timer',
        () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(minutes: 10));
        expect(monitor.warningVisible.value, isTrue);

        monitor.extendSession();
        expect(monitor.warningVisible.value, isFalse);
        expect(entry.auth.session.value, isA<ActiveSession>());

        async.elapse(const Duration(minutes: 10));
        expect(monitor.warningVisible.value, isTrue);

        monitor.dispose();
      });
    });

    test('the grace timer signs every active session out locally', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry1 = _activeEntry(id: 's1');
        final entry2 = _activeEntry(id: 's2');
        servers.value = {entry1.serverId: entry1, entry2.serverId: entry2};

        async.elapse(const Duration(minutes: 15));

        expect(entry1.auth.session.value, isA<NoSession>());
        expect(entry2.auth.session.value, isA<NoSession>());
        expect(monitor.warningVisible.value, isFalse);

        monitor.dispose();
      });
    });

    test('logoutNow signs out immediately and dismisses the dialog', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(minutes: 10));
        expect(monitor.warningVisible.value, isTrue);

        monitor.logoutNow();

        expect(entry.auth.session.value, isA<NoSession>());
        expect(monitor.warningVisible.value, isFalse);

        monitor.dispose();
      });
    });

    test(
        'losing the last active session cancels the timer and hides '
        'the dialog', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(minutes: 10));
        expect(monitor.warningVisible.value, isTrue);

        entry.auth.logout();

        expect(monitor.warningVisible.value, isFalse);

        async.elapse(const Duration(hours: 1));
        expect(monitor.warningVisible.value, isFalse);

        monitor.dispose();
      });
    });

    test('disabled config never schedules timers', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(
          servers: servers,
          config: InactivityConfig.disabled,
        );
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(hours: 1));

        expect(monitor.warningVisible.value, isFalse);
        expect(entry.auth.session.value, isA<ActiveSession>());

        monitor.dispose();
      });
    });

    test('dispose cancels pending timers', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        async.elapse(const Duration(minutes: 5));
        monitor.dispose();
        async.elapse(const Duration(minutes: 30));

        expect(entry.auth.session.value, isA<ActiveSession>());
      });
    });

    test('grace logout marks the inactivity flag for each active entry', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final flags = InMemoryInactivityLogoutFlagStorage();
        final monitor = InactivityMonitor(
          servers: servers,
          config: _config,
          inactivityLogoutFlags: flags,
        );
        final entry1 = _activeEntry(id: 's1');
        final entry2 = _activeEntry(id: 's2');
        servers.value = {entry1.serverId: entry1, entry2.serverId: entry2};

        async.elapse(const Duration(minutes: 15));
        async.flushMicrotasks();

        expect(flags.marked, containsAll([entry1.serverId, entry2.serverId]));

        monitor.dispose();
      });
    });

    test('graceDeadline is set when the warning shows, cleared on extend', () {
      fakeAsync((async) {
        final servers = Signal<Map<String, ServerEntry>>({});
        final monitor = InactivityMonitor(servers: servers, config: _config);
        final entry = _activeEntry();
        servers.value = {entry.serverId: entry};

        expect(monitor.graceDeadline.value, isNull);

        async.elapse(const Duration(minutes: 10));
        expect(monitor.graceDeadline.value, isNotNull);

        monitor.extendSession();
        expect(monitor.graceDeadline.value, isNull);

        monitor.dispose();
      });
    });
  });
}
