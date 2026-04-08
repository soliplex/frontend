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
      expect(selections.get('room-1', 'thread-1'), isEmpty);
    });

    test('stores and retrieves selection', () {
      selections.set('room-1', 'thread-1', {_doc1, _doc2});
      expect(selections.get('room-1', 'thread-1'), {_doc1, _doc2});
    });

    test('selections are independent per thread', () {
      selections.set('room-1', 'thread-1', {_doc1});
      selections.set('room-1', 'thread-2', {_doc2});

      expect(selections.get('room-1', 'thread-1'), {_doc1});
      expect(selections.get('room-1', 'thread-2'), {_doc2});
    });

    test('selections are independent per room', () {
      selections.set('room-1', 'thread-1', {_doc1});
      selections.set('room-2', 'thread-1', {_doc2});

      expect(selections.get('room-1', 'thread-1'), {_doc1});
      expect(selections.get('room-2', 'thread-1'), {_doc2});
    });

    test('setting empty set removes the entry', () {
      selections.set('room-1', 'thread-1', {_doc1});
      selections.set('room-1', 'thread-1', {});

      expect(selections.get('room-1', 'thread-1'), isEmpty);
    });

    test('supports null threadId', () {
      selections.set('room-1', null, {_doc1});
      expect(selections.get('room-1', null), {_doc1});
      expect(selections.get('room-1', 'thread-1'), isEmpty);
    });
  });

  group('migrateToThread', () {
    test('moves null-key selection to thread', () {
      selections.set('room-1', null, {_doc1, _doc2});
      selections.migrateToThread('room-1', 'thread-1');

      expect(selections.get('room-1', null), isEmpty);
      expect(selections.get('room-1', 'thread-1'), {_doc1, _doc2});
    });

    test('no-op when null key is empty', () {
      selections.migrateToThread('room-1', 'thread-1');
      expect(selections.get('room-1', 'thread-1'), isEmpty);
    });

    test('does not affect other rooms', () {
      selections.set('room-1', null, {_doc1});
      selections.set('room-2', null, {_doc2});

      selections.migrateToThread('room-1', 'thread-1');

      expect(selections.get('room-1', 'thread-1'), {_doc1});
      expect(selections.get('room-2', null), {_doc2});
    });
  });
}
