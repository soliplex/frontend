import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/rag_state_overlay.dart';

const _doc = RagDocument(id: 'd1', title: 'Report');

RagDatabaseScope _scope({
  List<String> names = const ['papers', 'wiki', 'notes'],
  List<String> namespaces = const ['rag'],
}) =>
    RagDatabaseScope(
      byNamespace: {for (final namespace in namespaces) namespace: names},
    );

void main() {
  group('databaseSelectionIsOpen', () {
    test('a thread that does not exist yet is open', () {
      expect(
        databaseSelectionIsOpen(threadExists: false, threadIsEmpty: null),
        isTrue,
      );
    });

    test('an empty thread is open', () {
      expect(
        databaseSelectionIsOpen(threadExists: true, threadIsEmpty: true),
        isTrue,
      );
    });

    test('a thread with a message is open, to additions', () {
      expect(
        databaseSelectionIsOpen(threadExists: true, threadIsEmpty: false),
        isTrue,
      );
    });

    test('a thread whose history is still loading is closed', () {
      expect(
        databaseSelectionIsOpen(threadExists: true, threadIsEmpty: null),
        isFalse,
      );
    });
  });

  group('searchedDatabasesFor', () {
    test('is null for a thread that does not exist yet', () {
      expect(
        searchedDatabasesFor(
          threadExists: false,
          threadIsEmpty: null,
          recorded: const {'wiki'},
          stored: const {'wiki'},
        ),
        isNull,
      );
    });

    test('is what is on record', () {
      expect(
        searchedDatabasesFor(
          threadExists: true,
          threadIsEmpty: false,
          recorded: const {'wiki'},
          stored: const {'wiki', 'papers'},
        ),
        equals({'wiki'}),
      );
    });

    test('is the stored selection for a thread with messages and no record',
        () {
      expect(
        searchedDatabasesFor(
          threadExists: true,
          threadIsEmpty: false,
          recorded: null,
          stored: const {'papers'},
        ),
        equals({'papers'}),
      );
    });

    test('is null for an empty thread with no record', () {
      expect(
        searchedDatabasesFor(
          threadExists: true,
          threadIsEmpty: true,
          recorded: null,
          stored: const {'papers'},
        ),
        isNull,
      );
    });
  });

  group('lockedDatabasesIn', () {
    test('locks nothing when nothing was searched', () {
      expect(lockedDatabasesIn(_scope(), null), isEmpty);
    });

    test('locks every database when every one was searched', () {
      expect(
        lockedDatabasesIn(_scope(), const {}),
        equals({'papers', 'wiki', 'notes'}),
      );
    });

    test('locks the searched ones the room still lists', () {
      expect(
        lockedDatabasesIn(_scope(), const {'wiki', 'gone'}),
        equals({'wiki'}),
      );
    });
  });

  group('buildRagStateOverlay', () {
    test('is null when nothing applies', () {
      expect(
        buildRagStateOverlay(
          filterEnabled: false,
          selectedDocuments: const {},
          scope: RagDatabaseScope.none,
          selectedDatabases: const {},
          clearsNarrowedSources: false,
        ),
        isNull,
      );
    });

    test('a single database sends no sources even with filtering on', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: true,
        selectedDocuments: const {},
        scope: _scope(names: const ['only']),
        selectedDatabases: const {'only'},
        clearsNarrowedSources: false,
      );
      expect(
          overlay,
          equals({
            'rag': {'document_filter': null},
          }));
    });

    test('a single database clears a narrowed selection the thread carries',
        () {
      final overlay = buildRagStateOverlay(
        filterEnabled: false,
        selectedDocuments: const {},
        scope: _scope(names: const ['only']),
        selectedDatabases: const {},
        clearsNarrowedSources: true,
      );
      expect(
          overlay,
          equals({
            'rag': {'sources': null},
          }));
    });

    test('a cleared selection merges with the filter under rag', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: true,
        selectedDocuments: const {},
        scope: _scope(names: const ['only']),
        selectedDatabases: const {},
        clearsNarrowedSources: true,
      );
      expect(
          overlay,
          equals({
            'rag': {'document_filter': null, 'sources': null},
          }));
    });

    test('sends null sources for the default selection', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: false,
        selectedDocuments: const {},
        scope: _scope(),
        selectedDatabases: const {},
        clearsNarrowedSources: false,
      );
      expect(
          overlay,
          equals({
            'rag': {'sources': null},
          }));
    });

    test('sends the selection in manifest order, dropping unknown names', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: false,
        selectedDocuments: const {},
        scope: _scope(),
        selectedDatabases: const {'notes', 'gone', 'papers'},
        clearsNarrowedSources: false,
      );
      expect(
          overlay,
          equals({
            'rag': {
              'sources': ['papers', 'notes'],
            },
          }));
    });

    test('a selection of only unknown names reads as the default', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: false,
        selectedDocuments: const {},
        scope: _scope(),
        selectedDatabases: const {'gone'},
        clearsNarrowedSources: false,
      );
      expect((overlay!['rag'] as Map)['sources'], isNull);
    });

    test('merges the filter and the selection under rag', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: true,
        selectedDocuments: {_doc},
        scope: _scope(),
        selectedDatabases: const {'wiki'},
        clearsNarrowedSources: false,
      );
      final rag = overlay!['rag'] as Map<String, dynamic>;
      expect(rag.keys, unorderedEquals(['document_filter', 'sources']));
      expect(rag['document_filter'], buildDocumentFilter(const [_doc]));
      expect(rag['sources'], equals(['wiki']));
    });

    test('sends each namespace only the names it searches', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: false,
        selectedDocuments: const {},
        scope: RagDatabaseScope(
          byNamespace: const {
            'rag': ['a', 'b'],
            'analysis': ['b', 'c'],
          },
        ),
        selectedDatabases: const {'a', 'c'},
        clearsNarrowedSources: false,
      );
      expect(
          overlay,
          equals({
            'rag': {
              'sources': ['a'],
            },
            'analysis': {
              'sources': ['c'],
            },
          }));
    });

    test('a namespace the selection does not reach gets every database', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: false,
        selectedDocuments: const {},
        scope: RagDatabaseScope(
          byNamespace: const {
            'rag': ['a', 'b'],
            'analysis': ['c'],
          },
        ),
        selectedDatabases: const {'a'},
        clearsNarrowedSources: false,
      );
      expect((overlay!['analysis'] as Map)['sources'], isNull);
    });

    test('writes the selection alone to a second namespace', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: true,
        selectedDocuments: {_doc},
        scope: _scope(namespaces: const ['rag', 'analysis']),
        selectedDatabases: const {'wiki'},
        clearsNarrowedSources: false,
      );
      expect(overlay!.keys, unorderedEquals(['rag', 'analysis']));
      expect(
        overlay['analysis'],
        equals({
          'sources': ['wiki'],
        }),
      );
      expect(
        (overlay['rag'] as Map).containsKey('document_filter'),
        isTrue,
      );
    });
  });

  group('selectedDatabasesIn', () {
    test('keeps the stored names the room lists', () {
      expect(
        selectedDatabasesIn(const {'wiki'}, _scope()),
        equals({'wiki'}),
      );
    });

    test('drops a stored name the room no longer lists', () {
      expect(
        selectedDatabasesIn(const {'wiki', 'gone'}, _scope()),
        equals({'wiki'}),
      );
    });

    test('reads stored names covering every database as the default', () {
      expect(
        selectedDatabasesIn(const {'notes', 'papers', 'wiki'}, _scope()),
        isEmpty,
      );
    });

    test('reads only names the room no longer lists as the default', () {
      expect(selectedDatabasesIn(const {'gone'}, _scope()), isEmpty);
    });

    test('adds back what the thread searched', () {
      expect(
        selectedDatabasesIn(const {'papers'}, _scope(), searched: {'wiki'}),
        equals({'papers', 'wiki'}),
      );
    });

    test('reads a thread that searched every database as the default', () {
      expect(
        selectedDatabasesIn(const {'papers'}, _scope(), searched: const {}),
        isEmpty,
      );
    });

    test('keeps the default when the thread searched less', () {
      expect(
        selectedDatabasesIn(const {}, _scope(), searched: {'wiki'}),
        isEmpty,
      );
    });

    test('reads a single-database room as the default', () {
      expect(
        selectedDatabasesIn(const {'only'}, _scope(names: const ['only'])),
        isEmpty,
      );
    });
  });

  group('toggledDatabases', () {
    test('deselecting from the default keeps every other database', () {
      expect(
        toggledDatabases(_scope(), const {}, 'wiki', selected: false),
        equals({'papers', 'notes'}),
      );
    });

    test('selecting adds to a narrowed selection', () {
      expect(
        toggledDatabases(_scope(), const {'papers'}, 'wiki', selected: true),
        equals({'papers', 'wiki'}),
      );
    });

    test('selecting the last missing database returns to the default', () {
      expect(
        toggledDatabases(
          _scope(),
          const {'papers', 'wiki'},
          'notes',
          selected: true,
        ),
        isEmpty,
      );
    });

    test('a searched database cannot be deselected', () {
      expect(
        toggledDatabases(
          _scope(),
          const {'papers', 'wiki'},
          'papers',
          selected: false,
          locked: {'papers'},
        ),
        isNull,
      );
    });

    test('an addition not yet sent can be deselected', () {
      expect(
        toggledDatabases(
          _scope(),
          const {'papers', 'wiki'},
          'wiki',
          selected: false,
          locked: {'papers'},
        ),
        equals({'papers'}),
      );
    });

    test('the last selected database cannot be deselected', () {
      expect(
        toggledDatabases(_scope(), const {'wiki'}, 'wiki', selected: false),
        isNull,
      );
    });
  });
}
