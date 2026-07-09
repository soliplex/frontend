import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/document_selections.dart';

const _doc1 = RagDocument(id: '1', title: 'Report');
const _doc2 = RagDocument(id: '2', title: 'Summary');

void main() {
  late DocumentSelections selections;

  setUp(() => selections = DocumentSelections());

  group('get and set', () {
    test('returns empty set for unknown key', () {
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
    });

    test('stores and retrieves selection', () {
      selections.set(
          serverId: 's1',
          roomId: 'room-1',
          threadId: 't1',
          docs: {_doc1, _doc2});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {_doc1, _doc2});
    });

    test('selections are independent per thread', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', docs: {_doc1});
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't2', docs: {_doc2});

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {_doc1});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't2'),
          {_doc2});
    });

    test('selections are independent per room', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', docs: {_doc1});
      selections
          .set(serverId: 's1', roomId: 'room-2', threadId: 't1', docs: {_doc2});

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {_doc1});
      expect(selections.get(serverId: 's1', roomId: 'room-2', threadId: 't1'),
          {_doc2});
    });

    test('selections are independent per server', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', docs: {_doc1});
      selections
          .set(serverId: 's2', roomId: 'room-1', threadId: 't1', docs: {_doc2});

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {_doc1});
      expect(selections.get(serverId: 's2', roomId: 'room-1', threadId: 't1'),
          {_doc2});
    });

    test('setting empty set removes the entry', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', docs: {_doc1});
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', docs: {});

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
    });

    test('supports null threadId', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: null, docs: {_doc1});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: null),
          {_doc1});
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
    });
  });

  group('clearThread', () {
    test('clearThread removes just that (server, room, thread)', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', docs: {_doc1});
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't2', docs: {_doc2});

      selections.clearThread(serverId: 's1', roomId: 'room-1', threadId: 't1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't2'),
          {_doc2});
    });
  });

  group('clearServer', () {
    test('drops the server\'s selections, keeping other servers\'', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: 't1', docs: {_doc1});
      selections
          .set(serverId: 's1', roomId: 'room-2', threadId: null, docs: {_doc1});
      selections
          .set(serverId: 's2', roomId: 'room-1', threadId: 't1', docs: {_doc2});

      selections.clearServer('s1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
      expect(selections.get(serverId: 's1', roomId: 'room-2', threadId: null),
          isEmpty);
      expect(selections.get(serverId: 's2', roomId: 'room-1', threadId: 't1'),
          {_doc2});
    });
  });

  group('migrateToThread', () {
    test('moves null-key selection to thread', () {
      selections.set(
          serverId: 's1',
          roomId: 'room-1',
          threadId: null,
          docs: {_doc1, _doc2});
      selections.migrateToThread(
          serverId: 's1', roomId: 'room-1', threadId: 't1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: null),
          isEmpty);
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {_doc1, _doc2});
    });

    test('no-op when null key is empty', () {
      selections.migrateToThread(
          serverId: 's1', roomId: 'room-1', threadId: 't1');
      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          isEmpty);
    });

    test('does not affect other rooms', () {
      selections
          .set(serverId: 's1', roomId: 'room-1', threadId: null, docs: {_doc1});
      selections
          .set(serverId: 's1', roomId: 'room-2', threadId: null, docs: {_doc2});

      selections.migrateToThread(
          serverId: 's1', roomId: 'room-1', threadId: 't1');

      expect(selections.get(serverId: 's1', roomId: 'room-1', threadId: 't1'),
          {_doc1});
      expect(selections.get(serverId: 's1', roomId: 'room-2', threadId: null),
          {_doc2});
    });
  });
}
