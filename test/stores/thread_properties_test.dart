import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        AuthException,
        NetworkException,
        PermissionDeniedException,
        ThreadInfo,
        ThreadLabel;
import 'package:soliplex_frontend/src/stores/thread_properties.dart';

import '../helpers/fakes.dart';

ThreadLabel _label(int id) =>
    ThreadLabel(id: id, name: 'L$id', color: '#42D76D');

ThreadInfo _thread({
  List<int> labels = const [],
  String name = 'Alpha',
  String description = '',
}) =>
    ThreadInfo(
      id: 't1',
      roomId: 'r1',
      name: name,
      description: description,
      createdAt: DateTime.utc(2026),
      lastActivity: DateTime.utc(2026, 5),
      labels: [for (final id in labels) _label(id)],
    );

/// A fake whose catalogue holds labels 1 to 4 and whose copy of the
/// thread carries [onServer].
FakeSoliplexApi _api({List<int> onServer = const []}) => FakeSoliplexApi()
  ..labels = [for (var id = 1; id <= 4; id++) _label(id)]
  ..allThreads = [_thread(labels: onServer)];

Future<ThreadPropertiesSaved> _save(
  FakeSoliplexApi api, {
  ThreadInfo? thread,
  String name = 'Alpha',
  String description = '',
  Set<int> initial = const {},
  Set<int> picked = const {},
  void Function(AuthException)? onAuthFailure,
}) =>
    saveThreadProperties(
      api,
      thread ?? _thread(labels: initial.toList()),
      name: name,
      description: description,
      initialLabelIds: initial,
      labelIds: picked,
      onAuthFailure: onAuthFailure ?? (_) {},
    );

void main() {
  group('saveThreadProperties', () {
    test('refuses a blank name without writing anything', () async {
      final api = _api();

      final saved = await _save(api, name: '   ');

      expect(saved.thread, isNull);
      expect(saved.error, isNotNull);
      expect(api.updateMetadataCallCount, 0);
      expect(api.setThreadLabelsCalls, isEmpty);
    });

    test('sends an empty description as null, so it is cleared', () async {
      final api = _api();

      await _save(api, description: '  ');

      expect(api.lastUpdatedDescription, isNull);
    });

    test('returns the saved thread, keeping its activity time', () async {
      final api = _api();

      final saved = await _save(
        api,
        name: ' Renamed ',
        description: 'About',
        picked: {2},
      );

      expect(saved.error, isNull);
      final thread = saved.thread!;
      expect(thread.name, 'Renamed');
      expect(thread.description, 'About');
      expect(thread.labels.map((l) => l.id), [2]);
      // The labels response carries no activity time; the row's stays.
      expect(thread.lastActivity, DateTime.utc(2026, 5));
    });

    test('keeps a label the assistant added after the dialog opened', () async {
      // The dialog saw no labels; the assistant has since added 3.
      final api = _api(onServer: [3]);

      await _save(api, picked: {1});

      expect(api.setThreadLabelsCalls.single.labelIds.toSet(), {3, 1});
    });

    test('removes only what the user removed', () async {
      final api = _api(onServer: [1, 2, 3]);

      await _save(api, initial: {1, 2}, picked: {2});

      expect(api.setThreadLabelsCalls.single.labelIds.toSet(), {2, 3});
    });

    test('drops a label deleted since the dialog opened', () async {
      // Label 4 was deleted, so the server no longer has it on the thread.
      final api = _api(onServer: [1]);

      final saved = await _save(api, initial: {1, 4}, picked: {1, 4});

      expect(saved.error, isNull);
      expect(api.setThreadLabelsCalls.single.labelIds, [1]);
    });

    test("falls back to the dialog's copy when the thread can't be read",
        () async {
      final api = _api(onServer: [3])
        ..nextGetThreadError = const NetworkException(message: 'down');

      await _save(api, initial: {1}, picked: {1, 2});

      expect(api.setThreadLabelsCalls.single.labelIds.toSet(), {1, 2});
    });

    test('says which half failed when the labels do not save', () async {
      final api = _api()
        ..nextSetThreadLabelsError =
            const NetworkException(message: 'connection reset');

      final saved = await _save(api, name: 'Renamed', picked: {1});

      // The name landed, so the row should show it.
      expect(saved.thread?.name, 'Renamed');
      expect(saved.error, startsWith('Saved the name and description'));
    });

    test('a lost session reports failure and asks for sign-in', () async {
      final api = _api()
        ..nextUpdateMetadataError = const AuthException(message: '401');
      AuthException? funnelled;

      final saved = await _save(api, onAuthFailure: (e) => funnelled = e);

      expect(saved.thread, isNull);
      expect(saved.error, contains('Sign in again'));
      expect(funnelled, isNotNull);
    });

    test('a refusal is not offered as something to retry', () async {
      final api = _api()
        ..nextUpdateMetadataError =
            const PermissionDeniedException(message: 'no');

      final saved = await _save(api);

      expect(saved.error, contains("don't have permission"));
      expect(saved.error, isNot(contains('try again')));
    });
  });

  group('currentThreadProperties', () {
    test("takes the server's name, description and labels", () async {
      final api = FakeSoliplexApi()
        ..allThreads = [
          _thread(name: 'Titled by the assistant', labels: [3]),
        ];
      final held = _thread(name: '');

      final current = await currentThreadProperties(
        api,
        held,
        onAuthFailure: (_) {},
      );

      expect(current.name, 'Titled by the assistant');
      expect(current.labels.map((l) => l.id), [3]);
      expect(current.lastActivity, held.lastActivity);
    });

    test('opens with the held copy when the read fails', () async {
      final api = FakeSoliplexApi()
        ..nextGetThreadError = const NetworkException(message: 'down');
      final held = _thread(name: 'Held');

      final current = await currentThreadProperties(
        api,
        held,
        onAuthFailure: (_) {},
      );

      expect(current.name, 'Held');
    });
  });
}
