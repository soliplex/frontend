import 'package:soliplex_client/src/application/rag_snapshot.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:test/test.dart';

void main() {
  group('RagSnapshot behavior', () {
    test('citationIds returns the raw string list', () {
      final json = {
        'citation_index': {
          'a': {
            'chunk_id': 'a',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
          'b': {
            'chunk_id': 'b',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
        },
        'citations': ['a', 'b'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.citationIds, equals(['a', 'b']));
    });

    test('resolveCitation looks up via citation_index', () {
      final json = {
        'citation_index': {
          'a': {
            'chunk_id': 'a',
            'content': 'content-a',
            'document_id': 'd1',
            'document_uri': 'uri-a',
          },
        },
        'citations': ['a'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      final citation = snapshot.resolveCitation('a');
      expect(citation, isNotNull);
      expect(citation!.content, equals('content-a'));
    });

    test('resolveCitation returns null for ids not in citation_index', () {
      final json = {
        'citation_index': <String, dynamic>{},
        'citations': ['orphan'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.resolveCitation('orphan'), isNull);
    });

    test('empty state yields empty citationIds and null resolve', () {
      final snapshot = RagSnapshot.fromJson(<String, dynamic>{});
      expect(snapshot.citationIds, isEmpty);
      expect(snapshot.resolveCitation('any'), isNull);
    });

    test('tolerates non-String entries in citations', () {
      // One bad entry must not drop the whole snapshot.
      final json = <String, dynamic>{
        'citation_index': {
          'c1': {
            'chunk_id': 'c1',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
          'c2': {
            'chunk_id': 'c2',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
        },
        'citations': <dynamic>['c1', null, 42, 'c2'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.citationIds, equals(['c1', 'c2']));
      expect(snapshot.resolveCitation('c1'), isNotNull);
      expect(snapshot.resolveCitation('c2'), isNotNull);
    });

    test('warns when citations is present but not a List', () {
      // Container drift (a Map/String where a list is expected) drops every
      // id for the namespace. Left silent, the source list renders short with
      // no trace — so it must be surfaced.
      final sink = _RecordingSink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      final snapshot = RagSnapshot.fromJson(<String, dynamic>{
        'citation_index': <String, dynamic>{},
        'citations': {'wrong': 'shape'},
      });

      expect(snapshot.citationIds, isEmpty);
      expect(sink.records, hasLength(1));
      expect(sink.records.single.level, LogLevel.warning);
      expect(sink.records.single.message, contains('citations'));
    });

    test('never logs the query of a malformed searches entry', () {
      // haiku.rag keys `searches` by the query text, which the model writes
      // and which can echo what the user typed.
      const query = 'what the user typed';
      final sink = _RecordingSink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      RagSnapshot.fromJson(<String, dynamic>{
        'citation_index': <String, dynamic>{},
        'citations': <String>[],
        'searches': <String, dynamic>{
          query: 'not a list',
          '$query, again': <dynamic>[
            'not a map',
            <String, dynamic>{
              'document_id': 7,
              'image_data': {'#/pictures/0': 'AAAA'},
            },
          ],
        },
      });

      expect(sink.records, hasLength(3));
      for (final record in sink.records) {
        expect(record.message, isNot(contains(query)));
        expect(record.attributes.values, isNot(contains(contains(query))));
      }
    });

    test('warns when citation_index is present but not a Map', () {
      final sink = _RecordingSink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      final snapshot = RagSnapshot.fromJson(<String, dynamic>{
        'citation_index': ['wrong', 'shape'],
        'citations': ['a'],
      });

      expect(snapshot.resolveCitation('a'), isNull);
      expect(sink.records, hasLength(1));
      expect(sink.records.single.level, LogLevel.warning);
      expect(sink.records.single.message, contains('citation_index'));
    });

    test('tolerates malformed citation_index entries', () {
      // One valid entry, one non-Map, one missing required field.
      final json = <String, dynamic>{
        'citation_index': <String, dynamic>{
          'c1': {
            'chunk_id': 'c1',
            'content': 't',
            'document_id': 'd',
            'document_uri': 'u',
          },
          'c2': 'not a map',
          'c3': {'chunk_id': 'c3'}, // missing required fields
        },
        'citations': ['c1', 'c2', 'c3'],
      };
      final snapshot = RagSnapshot.fromJson(json);
      expect(snapshot.citationIds, equals(['c1', 'c2', 'c3']));
      expect(snapshot.resolveCitation('c1'), isNotNull);
      expect(snapshot.resolveCitation('c2'), isNull);
      expect(snapshot.resolveCitation('c3'), isNull);
    });
  });

  group('withEmptyRunScopedKeys', () {
    test('empties the run-scoped keys, preserves the cumulative index', () {
      final cleared = RagSnapshot.withEmptyRunScopedKeys({
        'analysis': {
          'citation_index': {'a': <String, dynamic>{}},
          'citations': ['a'],
          'searches': {'q': <dynamic>[]},
          'executions': [
            {'code': 'print(1)', 'stdout': '1'},
          ],
          'document_filter': 'id IN (1)',
        },
      });

      final analysis = cleared['analysis'] as Map<String, dynamic>;
      expect(analysis['citations'], isEmpty);
      expect(analysis['searches'], isEmpty);
      expect(analysis['executions'], isEmpty);
      expect(analysis['citation_index'], equals({'a': <String, dynamic>{}}));
      expect(analysis['document_filter'], equals('id IN (1)'));
    });

    // The pre-0.41 shape (haiku.rag 0.33.0–0.40.1): whole citations in
    // `citations`, no `citation_index`. Field order as that version dumped it.
    Map<String, dynamic> legacyCitation() => {
          'index': 1,
          'document_id': 'doc-1',
          'chunk_id': 'chunk-1',
          'document_uri': 'file:///x.pdf',
          'document_title': 'T',
          'page_numbers': [3],
          'headings': ['H'],
          'content': '...cted and edge devices.',
        };

    test('empties a pre-0.41 block that has citations but no citation_index',
        () {
      final state = <String, dynamic>{
        'rag': <String, dynamic>{
          'citations': [legacyCitation()],
          'searches': {
            'q': [
              {'content': 'c', 'score': 0.5},
            ],
          },
          'document_filter': "id = 'doc-1'",
          'qa_history': [
            {'question': 'q'},
          ],
        },
      };

      final rag = RagSnapshot.withEmptyRunScopedKeys(state)['rag']
          as Map<String, dynamic>;

      expect(rag['citations'], isEmpty);
      expect(rag['searches'], isEmpty);
      expect(rag['document_filter'], "id = 'doc-1'");
      expect(rag['qa_history'], [
        {'question': 'q'},
      ]);
    });

    test('empties a citations value that is null', () {
      final rag = RagSnapshot.withEmptyRunScopedKeys({
        'rag': <String, dynamic>{'citations': null},
      })['rag'] as Map<String, dynamic>;

      expect(rag['citations'], isEmpty);
    });

    test('leaves a block without a citation_index untouched outside rag', () {
      // A capability entry point may name its own namespace and keys; only
      // `rag` ever stored the pre-0.41 shape.
      final state = <String, dynamic>{
        'citation_policy': <String, dynamic>{
          'violations': [1],
        },
        'some-plugin': <String, dynamic>{
          'citations': [
            {'title': 'not a haiku.rag citation'},
          ],
          'searches': {
            'q': ['kept'],
          },
        },
      };

      expect(RagSnapshot.withEmptyRunScopedKeys(state), state);
      expect(RagSnapshot.carriesNonIdCitations(state), isFalse);
    });

    test('does not add a key the namespace does not carry', () {
      // `rag` in state stored by haiku.rag 0.84.0 has no `executions`;
      // inventing one makes the outbound run_input.state misleading to read
      // in the network inspector.
      final cleared = RagSnapshot.withEmptyRunScopedKeys({
        'rag': {
          'citation_index': <String, dynamic>{},
          'citations': ['a'],
        },
      });
      expect(
        (cleared['rag'] as Map<String, dynamic>).keys,
        equals(['citation_index', 'citations']),
      );
    });

    test('does not mutate the input', () {
      final original = <String, dynamic>{
        'rag': {
          'citation_index': <String, dynamic>{},
          'citations': ['a'],
        },
      };
      RagSnapshot.withEmptyRunScopedKeys(original);
      expect((original['rag'] as Map)['citations'], equals(['a']));
    });
  });

  group('fromJson skip logging', () {
    test('logs whole citations once per block, not once per entry', () {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      RagSnapshot.fromJson({
        'citations': [
          for (var i = 0; i < 3; i++) {'chunk_id': 'c$i', 'content': 'x'},
        ],
      });

      final skips =
          sink.records.where((r) => r.message.contains('citations')).toList();
      expect(skips, hasLength(1));
      expect(skips.single.attributes, {'skipped': 3});
    });
  });

  group('withUnreadableCitationsDropped', () {
    test('drops citation_index entries that are not objects or do not parse',
        () {
      final cleared = RagSnapshot.withUnreadableCitationsDropped({
        'analysis': <String, dynamic>{
          'citations': <String>[],
          'citation_index': <String, dynamic>{
            'a': {
              'chunk_id': 'a',
              'content': 't',
              'document_id': 'd',
              'document_uri': 'u',
            },
            'b': <String, dynamic>{'chunk_id': 'b', 'content': 't'},
            'c': 7,
          },
        },
      });

      final index = (cleared['analysis'] as Map)['citation_index'] as Map;
      expect(index.keys, ['a']);
    });

    test('logs what it drops without the entries', () {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      RagSnapshot.withUnreadableCitationsDropped({
        'rag': <String, dynamic>{
          'citations': <String>[],
          'citation_index': <String, dynamic>{
            'secret-chunk': <String, dynamic>{'content': 'secret-text'},
          },
        },
      });

      final record = sink.records.singleWhere(
        (r) => r.message.contains('Dropped'),
      );
      expect(record.attributes, {'namespace': 'rag', 'dropped': 1});
      expect(
        '${record.message} ${record.attributes}',
        isNot(contains('secret')),
      );
    });

    test('sends a citation_index that is not a map as empty', () {
      final cleared = RagSnapshot.withUnreadableCitationsDropped({
        'rag': <String, dynamic>{
          'citations': ['a'],
          'citation_index': 'nope',
        },
      });

      expect((cleared['rag'] as Map)['citation_index'], <String, dynamic>{});
    });
  });

  group('buildRagDocumentFilterOverlay', () {
    test('wraps a filter string under rag.document_filter', () {
      final overlay = buildRagDocumentFilterOverlay("id = 'abc'");
      expect(
        overlay,
        equals({
          'rag': {'document_filter': "id = 'abc'"},
        }),
      );
    });

    test('carries null filter through (signals "clear")', () {
      final overlay = buildRagDocumentFilterOverlay(null);
      expect(
        overlay,
        equals({
          'rag': {'document_filter': null},
        }),
      );
    });

    test('only touches rag.document_filter, no other rag fields', () {
      final overlay = buildRagDocumentFilterOverlay('x');
      final rag = overlay['rag'] as Map<String, dynamic>;
      expect(rag.keys, equals(['document_filter']));
    });
  });

  group('withRejectedScopeCleared', () {
    test(
        'a document_filter that is not a string becomes null in any '
        'namespace', () {
      final cleared = withRejectedScopeCleared({
        'rag': <String, dynamic>{'document_filter': 42},
        'analysis': <String, dynamic>{'document_filter': 42},
      });

      expect(cleared, {
        'rag': {'document_filter': null},
        'analysis': {'document_filter': null},
      });
    });

    test('sources that are not a list of names become null in any namespace',
        () {
      final cleared = withRejectedScopeCleared({
        'rag': <String, dynamic>{'sources': 'papers'},
        'analysis': <String, dynamic>{
          'sources': ['papers', 7],
        },
      });

      expect(cleared, {
        'rag': {'sources': null},
        'analysis': {'sources': null},
      });
    });

    test('keeps values the backend accepts', () {
      final state = {
        'rag': <String, dynamic>{
          'document_filter': 'id IS NOT NULL',
          'sources': ['papers'],
          'citations': ['chunk-1'],
        },
        'citation_policy': <String, dynamic>{},
      };

      expect(withRejectedScopeCleared(state), state);
    });
  });

  group('buildRagSourcesOverlay', () {
    test('writes the names under rag.sources by default', () {
      expect(
        buildRagSourcesOverlay(['papers', 'wiki']),
        equals({
          'rag': {
            'sources': ['papers', 'wiki'],
          },
        }),
      );
    });

    test('writes to every namespace given', () {
      final overlay = buildRagSourcesOverlay(
        ['papers'],
        namespaces: ['rag', 'analysis'],
      );
      expect(overlay.keys, equals(['rag', 'analysis']));
      expect(
        overlay['analysis'],
        equals({
          'sources': ['papers'],
        }),
      );
    });

    test('carries null through (every database)', () {
      expect(
        buildRagSourcesOverlay(null),
        equals({
          'rag': {'sources': null},
        }),
      );
    });

    test('normalises an empty list to null', () {
      final rag = buildRagSourcesOverlay([])['rag'] as Map<String, dynamic>;
      expect(rag.containsKey('sources'), isTrue);
      expect(rag['sources'], isNull);
    });

    test('only touches sources, no other fields', () {
      final rag = buildRagSourcesOverlay(['a'])['rag'] as Map<String, dynamic>;
      expect(rag.keys, equals(['sources']));
    });
  });
}

/// Captures records from the rag snapshot's logger, ignoring all other log
/// traffic the singleton sees so assertions stay strict.
class _RecordingSink implements LogSink {
  final List<LogRecord> records = [];

  @override
  void write(LogRecord record) {
    if (record.loggerName == 'soliplex_client.rag_snapshot') {
      records.add(record);
    }
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
