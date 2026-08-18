import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        ApiException,
        AuthException,
        NotFoundException,
        PermissionDeniedException,
        ThreadLabel;
import 'package:soliplex_frontend/src/modules/auth/auth_session.dart';
import 'package:soliplex_frontend/src/modules/auth/server_manager.dart';
import 'package:soliplex_frontend/src/modules/lobby/labels_state.dart';

import '../../helpers/fakes.dart';

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
}
