import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        ApiException,
        AuthException,
        NotFoundException,
        PermissionDeniedException,
        ThreadLabel;
import 'package:soliplex_agent/soliplex_agent.dart' show Signal;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/auth_tokens.dart';
import 'package:soliplex_frontend/src/modules/auth/server_entry.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/stores/labels_state.dart';

import '../helpers/fakes.dart';
import '../helpers/test_server_entry.dart';

class _Harness {
  _Harness({List<ThreadLabel>? labels}) {
    manager = ServerManager(
      authFactory: () => AuthSession(refreshService: FakeTokenRefreshService()),
      clientFactory: ({getToken, tokenRefresher}) => FakeHttpClient(),
      storage: InMemoryServerStorage(),
    );
    manager.addServer(
      serverId: 'local',
      serverUrl: Uri.parse('http://localhost:8000'),
      requiresAuth: false,
    );
    api = FakeSoliplexApi()..labels = labels ?? [];
    state = LabelsState(
      entryResolver: (id) => manager.servers.value[id],
      apiResolver: (_) => api,
    );
  }

  late final ServerManager manager;
  late final FakeSoliplexApi api;
  late final LabelsState state;

  Future<void> load() async {
    state.setServer('local');
    await pumpEventQueue();
  }

  void dispose() => state.dispose();
}

ThreadLabel _label(int id, String name, {int? usageCount}) => ThreadLabel(
      id: id,
      name: name,
      color: '#42D76D',
      usageCount: usageCount,
    );

void main() {
  group('LabelsState', () {
    test('loads the catalogue for the selected server', () async {
      final h = _Harness(labels: [_label(1, 'Manuals')]);

      await h.load();

      final loaded = h.state.labels.value as LabelsLoaded;
      expect(loaded.labels.single.name, equals('Manuals'));
      expect(h.state.current.single.name, equals('Manuals'));

      h.dispose();
    });

    test('clears when no server is selected', () async {
      final h = _Harness(labels: [_label(1, 'Manuals')]);
      await h.load();

      h.state.setServer(null);

      expect((h.state.labels.value as LabelsLoaded).labels, isEmpty);

      h.dispose();
    });

    test('reports an older server as unsupported, not failed', () async {
      // A 404 here means the server predates labels. Offering a retry
      // that will 404 forever reads as a bug.
      final h = _Harness()
        ..api.nextLabelsError = const NotFoundException(message: 'no route');

      await h.load();

      expect(h.state.labels.value, isA<LabelsUnsupported>());

      h.dispose();
    });

    test('reports a genuine failure as failed', () async {
      final h = _Harness()..api.nextLabelsError = Exception('boom');

      await h.load();

      expect(h.state.labels.value, isA<LabelsFailed>());

      h.dispose();
    });

    test('creates a label and folds it in without refetching', () async {
      final h = _Harness();
      await h.load();

      final reason = await h.state.create(name: 'Manuals');

      expect(reason, isNull);
      expect(h.state.current.single.name, equals('Manuals'));
      // Folded from the write response: the backend commits after
      // responding, so a refetch here could still return the old list.
      expect(h.api.createLabelCalls.single.name, equals('Manuals'));

      h.dispose();
    });

    test('keeps the catalogue sorted after a create', () async {
      final h = _Harness(labels: [_label(1, 'Manuals')]);
      await h.load();

      await h.state.create(name: 'Archived');

      expect(
        h.state.current.map((l) => l.name),
        equals(['Archived', 'Manuals']),
      );

      h.dispose();
    });

    test('updates a label in place', () async {
      final h = _Harness(labels: [_label(1, 'Manuals')]);
      await h.load();

      final reason = await h.state.update(1, name: 'Docs', color: '#ABCDEF');

      expect(reason, isNull);
      expect(h.state.current.single.name, equals('Docs'));
      expect(h.state.current.single.color, equals('#ABCDEF'));

      h.dispose();
    });

    test('deletes a label', () async {
      final h = _Harness(labels: [_label(1, 'Manuals'), _label(2, 'Urgent')]);
      await h.load();

      final reason = await h.state.delete(1);

      expect(reason, isNull);
      expect(h.state.current.map((l) => l.id), equals([2]));

      h.dispose();
    });

    test('explains a duplicate name rather than dumping the error', () async {
      // 409 is the one failure a user can act on, and there is no
      // dedicated exception type for it.
      final h = _Harness()
        ..api.nextCreateLabelError =
            const ApiException(message: 'HTTP 409', statusCode: 409);
      await h.load();

      final reason = await h.state.create(name: 'Manuals');

      expect(reason, contains('already exists'));

      h.dispose();
    });

    test('explains a refused write', () async {
      // Reachable even though the tab is administrators-only: access can
      // be revoked while the page is open.
      final h = _Harness(labels: [_label(1, 'Manuals')])
        ..api.nextDeleteLabelError =
            const PermissionDeniedException(message: 'HTTP 403');
      await h.load();

      final reason = await h.state.delete(1);

      expect(reason, contains('administrators'));
      // The label survives, because the delete did not happen.
      expect(h.state.current, hasLength(1));

      h.dispose();
    });

    test('deleting a label someone else deleted is a success', () async {
      final h = _Harness(labels: [_label(1, 'Manuals'), _label(2, 'Ops')])
        ..api.nextDeleteLabelError = const NotFoundException(message: 'gone');
      await h.load();

      final reason = await h.state.delete(1);

      expect(reason, isNull);
      expect(h.state.catalogue.value.map((l) => l.name), ['Ops']);

      h.dispose();
    });

    test('editing a label someone else deleted drops its row', () async {
      final h = _Harness(labels: [_label(1, 'Manuals'), _label(2, 'Ops')])
        ..api.nextUpdateLabelError = const NotFoundException(message: 'gone');
      await h.load();

      final reason = await h.state.update(1, name: 'Guides');

      expect(reason, contains('no longer exists'));
      expect(h.state.catalogue.value.map((l) => l.name), ['Ops']);

      h.dispose();
    });

    test('a retry after a failure shows that it is loading', () async {
      final h = _Harness()..api.nextLabelsError = Exception('boom');
      await h.load();
      expect(h.state.labels.value, isA<LabelsFailed>());

      h.api.nextLabelsError = null;
      final retry = h.state.refresh();
      expect(h.state.labels.value, isA<LabelsLoading>());
      await retry;
      expect(h.state.labels.value, isA<LabelsLoaded>());

      h.dispose();
    });

    test('explains a lost session', () async {
      final h = _Harness()
        ..api.nextCreateLabelError = const AuthException(message: 'HTTP 401');
      await h.load();

      final reason = await h.state.create(name: 'Manuals');

      expect(reason, contains('signed in'));

      h.dispose();
    });

    test('falls back to a generic reason for anything else', () async {
      final h = _Harness()..api.nextCreateLabelError = Exception('boom');
      await h.load();

      final reason = await h.state.create(name: 'Manuals');

      expect(reason, contains('Could not save'));
      // Never the raw exception: 'Exception: boom' is not a sentence.
      expect(reason, isNot(contains('boom')));

      h.dispose();
    });

    test('marks busy while a mutation runs', () async {
      final h = _Harness();
      await h.load();

      expect(h.state.busy.value, isFalse);
      final pending = h.state.create(name: 'Manuals');
      expect(h.state.busy.value, isTrue);
      await pending;
      expect(h.state.busy.value, isFalse);

      h.dispose();
    });

    test('discards a load that lands after dispose', () async {
      final h = _Harness(labels: [_label(1, 'Manuals')]);
      h.state.setServer('local');

      h.state.dispose();
      await pumpEventQueue();

      // Still the initial state: a late write would repaint a disposed
      // tab.
      expect(h.state.labels.value, isA<LabelsLoading>());
    });

    test('refuses to mutate with no server selected', () async {
      final h = _Harness();

      final reason = await h.state.create(name: 'Manuals');

      expect(reason, isNotNull);
      expect(h.api.createLabelCalls, isEmpty);

      h.dispose();
    });
  });

  group('LabelsState following the selection', () {
    test('a label created on one server is not folded into the next', () async {
      final h = _following();
      h.selection.value = _a;
      await pumpEventQueue();

      final held = h.apiA.holdNext('createLabel');
      final saving = h.state.create(name: 'Urgent');
      h.selection.value = _b;
      await pumpEventQueue();
      held.complete();

      expect(await saving, isNull);
      expect(h.names(), ['Billing']);
      h.dispose();
    });

    test("a catalogue from the old server never lands on the new one's",
        () async {
      final h = _following();
      final held = h.apiA.holdNext('getLabels');
      h.selection.value = _a;
      h.selection.value = _b;
      await pumpEventQueue();

      held.complete();
      await pumpEventQueue();

      expect(h.names(), ['Billing']);
      h.dispose();
    });

    test('a create while the catalogue failed refetches instead', () async {
      final h = _following();
      h.apiA.nextLabelsError = Exception('boom');
      h.selection.value = _a;
      await pumpEventQueue();
      expect(h.state.labels.value, isA<LabelsFailed>());

      h.apiA.nextLabelsError = null;
      await h.state.create(name: 'Urgent');
      await pumpEventQueue();

      // The whole catalogue, not a one-label list hiding the failure.
      expect(h.names(), ['Manuals', 'Urgent']);
      expect(h.apiA.createLabelCalls, hasLength(1));
      h.dispose();
    });

    test('waits for sign-in, then loads', () async {
      final auth = AuthSession(refreshService: FakeTokenRefreshService());
      final h = _following(authA: auth);
      h.selection.value = _a;
      await pumpEventQueue();
      expect(h.state.labels.value, isA<LabelsLoading>());

      auth.login(
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
      await pumpEventQueue();

      expect(h.names(), ['Manuals']);
      h.dispose();
    });

    test('a rejected write sends the user to sign in again', () async {
      final h = _following();
      h.selection.value = _a;
      await pumpEventQueue();
      h.apiA.nextCreateLabelError = const AuthException(message: '401');

      await h.state.create(name: 'Urgent');

      expect(h.authA.session.value, isA<ExpiredSession>());
      // And the catalogue waits for the sign-in rather than showing it.
      expect(h.state.labels.value, isA<LabelsLoading>());
      h.dispose();
    });
  });
}

const _a = 'http://a:8000';
const _b = 'http://b:8000';

/// A catalogue following a selection across two servers that require
/// sign-in: A holds 'Manuals', B holds 'Billing', both with id 1.
({
  LabelsState state,
  FakeSoliplexApi apiA,
  AuthSession authA,
  Signal<String?> selection,
  List<String> Function() names,
  void Function() dispose,
}) _following({AuthSession? authA}) {
  final apiA = FakeSoliplexApi()..labels = [_label(1, 'Manuals')];
  final apiB = FakeSoliplexApi()..labels = [_label(1, 'Billing')];
  final sessionA = authA ?? authInActiveSession();
  final servers = Signal<Map<String, ServerEntry>>({
    _a: createTestServerEntry(
      api: apiA,
      serverId: _a,
      alias: 'a',
      requiresAuth: true,
      auth: sessionA,
    ),
    _b: createTestServerEntry(
      api: apiB,
      serverId: _b,
      alias: 'b',
      requiresAuth: true,
      auth: authInActiveSession(),
    ),
  });
  final selection = Signal<String?>(null);
  final state = LabelsState(entryResolver: (id) => servers.value[id]);
  final unfollow = state.follow(selection: selection, servers: servers);

  return (
    state: state,
    apiA: apiA,
    authA: sessionA,
    selection: selection,
    names: () => switch (state.labels.value) {
          LabelsLoaded(:final labels) => [for (final l in labels) l.name],
          _ => const <String>[],
        },
    dispose: () {
      unfollow();
      state.dispose();
    },
  );
}
