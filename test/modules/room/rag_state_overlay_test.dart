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
  group('buildRagStateOverlay', () {
    test('is null when nothing applies', () {
      expect(
        buildRagStateOverlay(
          filterEnabled: false,
          selectedDocuments: const {},
          scope: RagDatabaseScope.none,
          selectedDatabases: const {},
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
      );
      expect(
          overlay,
          equals({
            'rag': {'document_filter': null},
          }));
    });

    test('sends null sources for the default selection', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: false,
        selectedDocuments: const {},
        scope: _scope(),
        selectedDatabases: const {},
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
      );
      expect((overlay!['rag'] as Map)['sources'], isNull);
    });

    test('merges the filter and the selection under rag', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: true,
        selectedDocuments: {_doc},
        scope: _scope(),
        selectedDatabases: const {'wiki'},
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
      );
      expect((overlay!['analysis'] as Map)['sources'], isNull);
    });

    test('writes the selection alone to a second namespace', () {
      final overlay = buildRagStateOverlay(
        filterEnabled: true,
        selectedDocuments: {_doc},
        scope: _scope(namespaces: const ['rag', 'analysis']),
        selectedDatabases: const {'wiki'},
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
}
