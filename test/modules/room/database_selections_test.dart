import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/database_selections.dart';

void main() {
  late DatabaseSelections selections;

  setUp(() => selections = DatabaseSelections());

  group('get and set', () {
    test('returns empty set for an unknown key', () {
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
    });

    test('stores and retrieves a selection', () {
      selections.set(
          serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a', 'b'});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {'a', 'b'});
    });

    test('an empty set is kept as a deliberate reset', () {
      selections.set(
          serverId: 's1', roomId: 'room-1', threadId: 't1', names: const {});
      selections
          .seed(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
    });

    test('the stored set is a copy the caller cannot mutate', () {
      final names = {'a'};
      selections.set(
          serverId: 's1', roomId: 'room-1', threadId: 't1', names: names);
      names.add('b');
      final stored =
          selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1');
      expect(stored, {'a'});
      expect(() => stored.add('c'), throwsUnsupportedError);
    });

    test('selections are independent per thread and per server', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't2', names: {'b'});
      selections
          .set(serverId: 's2', roomId: 'room-1', threadId: 't1', names: {'c'});

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {'a'});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't2'),
          {'b'});
      expect(selections.get(serverId: 's2', roomId: 'room-1', threadId: 't1'),
          {'c'});
    });
  });

  group('seed', () {
    test('records a selection for a thread that has none', () {
      selections
          .seed(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {'a'});
    });

    test('leaves a selection the thread already has', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'b'});
      selections
          .seed(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {'b'});
    });
  });

  group('clearThread', () {
    test('drops the thread and leaves its siblings', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't2', names: {'b'});

      selections.clearThread(serverId: 's1', roomId: 'room-1', threadId: 't1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't2'),
          {'b'});
    });
  });

  group('clearServer', () {
    test('drops every selection for the server only', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});
      selections
          .set(serverId: 's1', roomId: 'room-2', threadId: null, names: {'b'});
      selections
          .set(serverId: 's2', roomId: 'room-1', threadId: 't1', names: {'c'});

      selections.clearServer('s1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
      expect(selections.get(serverId: 's1', roomId: 'room-2', threadId: null),
          isEmpty);
      expect(selections.get(serverId: 's2', roomId: 'room-1', threadId: 't1'),
          {'c'});
    });
  });

  group('migrateToThread', () {
    test('moves the pending selection onto the new thread', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: null, names: {'a'});

      selections.migrateToThread(
          serverId: 's1', roomId: 'room-1', threadId: 't1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: null),
          isEmpty);
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {'a'});
    });

    test('moves a deliberate reset too', () {
      selections.set(
          serverId: 's1', roomId: 'room-1', threadId: null, names: const {});

      selections.migrateToThread(
          serverId: 's1', roomId: 'room-1', threadId: 't1');
      selections
          .seed(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
    });

    test('is a no-op with nothing pending', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', names: {'a'});

      selections.migrateToThread(
          serverId: 's1', roomId: 'room-1', threadId: 't1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {'a'});
    });
  });
}
