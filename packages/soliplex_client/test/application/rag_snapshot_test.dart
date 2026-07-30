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

    test('leaves non-citation namespaces untouched', () {
      // A namespace without a `citation_index` is not citation-bearing, so it
      // is copied through whole — even when it happens to carry a key name the
      // run-scoped clear would otherwise empty.
      final cleared = RagSnapshot.withEmptyRunScopedKeys({
        'bubble-sandbox': {
          'anything': 1,
          'citations': ['not-a-citation'],
        },
      });
      expect(
        cleared['bubble-sandbox'],
        equals({
          'anything': 1,
          'citations': ['not-a-citation'],
        }),
      );
    });

    test('does not add a key the namespace does not carry', () {
      // `rag` has no `executions`; inventing one makes the outbound
      // run_input.state misleading to read in the network inspector.
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
