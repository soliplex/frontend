import 'package:soliplex_client/src/application/json_patch.dart';
import 'package:test/test.dart';

void main() {
  group('applyJsonPatch', () {
    group('add operation', () {
      test('adds value to root level', () {
        final state = <String, dynamic>{'existing': 'value'};
        final operations = [
          {'op': 'add', 'path': '/new', 'value': 'added'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['existing'], 'value');
        expect(result['new'], 'added');
      });

      test('adds nested value creating intermediate objects', () {
        final state = <String, dynamic>{};
        final operations = [
          {'op': 'add', 'path': '/a/b/c', 'value': 'deep'},
        ];

        final result = applyJsonPatch(state, operations);

        final a = result['a'] as Map<String, dynamic>;
        final b = a['b'] as Map<String, dynamic>;
        expect(b['c'], 'deep');
      });

      test('adds item to array at end', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/2', 'value': 'c'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'b', 'c']);
      });

      test('appends to array using RFC 6902 "-" syntax', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/-', 'value': 'c'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'b', 'c']);
      });

      test('appends to nested array using "-" syntax', () {
        final state = <String, dynamic>{
          'rag': {
            'qa_history': [
              {'question': 'Q1', 'answer': 'A1'},
            ],
          },
        };
        final operations = [
          {
            'op': 'add',
            'path': '/rag/qa_history/-',
            'value': {'question': 'Q2', 'answer': 'A2'},
          },
        ];

        final result = applyJsonPatch(state, operations);

        final qaHistory =
            (result['rag'] as Map<String, dynamic>)['qa_history'] as List;
        expect(qaHistory, hasLength(2));
        expect((qaHistory[1] as Map<String, dynamic>)['question'], 'Q2');
      });

      test('replaces item in array at index', () {
        final state = <String, dynamic>{
          'items': ['a', 'b', 'c'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/1', 'value': 'replaced'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'replaced', 'c']);
      });
    });

    group('replace operation', () {
      test('replaces existing value', () {
        final state = <String, dynamic>{'key': 'old'};
        final operations = [
          {'op': 'replace', 'path': '/key', 'value': 'new'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'new');
      });

      test('replaces nested value', () {
        final state = <String, dynamic>{
          'outer': {'inner': 'old'},
        };
        final operations = [
          {'op': 'replace', 'path': '/outer/inner', 'value': 'new'},
        ];

        final result = applyJsonPatch(state, operations);

        final outer = result['outer'] as Map<String, dynamic>;
        expect(outer['inner'], 'new');
      });
    });

    group('remove operation', () {
      test('removes value at root level', () {
        final state = <String, dynamic>{'keep': 'yes', 'remove': 'no'};
        final operations = [
          {'op': 'remove', 'path': '/remove'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result.containsKey('keep'), isTrue);
        expect(result.containsKey('remove'), isFalse);
      });

      test('removes nested value', () {
        final state = <String, dynamic>{
          'outer': {'keep': 'yes', 'remove': 'no'},
        };
        final operations = [
          {'op': 'remove', 'path': '/outer/remove'},
        ];

        final result = applyJsonPatch(state, operations);

        final outer = result['outer'] as Map<String, dynamic>;
        expect(outer['keep'], 'yes');
        expect(outer.containsKey('remove'), isFalse);
      });

      test('removes item from array', () {
        final state = <String, dynamic>{
          'items': ['a', 'b', 'c'],
        };
        final operations = [
          {'op': 'remove', 'path': '/items/1'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['items'], ['a', 'c']);
      });
    });

    group('multiple operations', () {
      test('applies operations in sequence', () {
        final state = <String, dynamic>{'count': 0};
        final operations = [
          {'op': 'add', 'path': '/name', 'value': 'test'},
          {'op': 'replace', 'path': '/count', 'value': 1},
          {'op': 'add', 'path': '/items', 'value': <dynamic>[]},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['count'], 1);
        expect(result['name'], 'test');
        expect(result['items'], isEmpty);
      });
    });

    group('error handling', () {
      test('skips invalid operation (not a map)', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          'not a map',
          {'op': 'add', 'path': '/new', 'value': 'added'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'value');
        expect(result['new'], 'added');
      });

      test('skips operation with missing op', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'path': '/key', 'value': 'changed'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'value');
      });

      test('skips operation with missing path', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'op': 'add', 'value': 'changed'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result['key'], 'value');
      });

      test('skips unsupported operations (move, copy, test)', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'op': 'move', 'from': '/key', 'path': '/newKey'},
          {'op': 'copy', 'from': '/key', 'path': '/keyCopy'},
          {'op': 'test', 'path': '/key', 'value': 'value'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result, equals({'key': 'value'}));
      });
    });

    group('immutability', () {
      test('does not modify original state', () {
        final state = <String, dynamic>{
          'nested': {'value': 'original'},
        };
        final operations = [
          {'op': 'replace', 'path': '/nested/value', 'value': 'modified'},
        ];

        applyJsonPatch(state, operations);

        final nested = state['nested'] as Map<String, dynamic>;
        expect(nested['value'], 'original');
      });

      test('does not modify original arrays', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/2', 'value': 'c'},
        ];

        applyJsonPatch(state, operations);

        expect(state['items'], ['a', 'b']);
      });
    });

    group('intermediate container creation', () {
      test('creates List when path segment is followed by numeric index', () {
        final state = <String, dynamic>{};
        final operations = [
          {
            'op': 'add',
            'path': '/rag/qa_history/0',
            'value': {'question': 'Q1'},
          },
        ];

        final result = applyJsonPatch(state, operations);

        final ragState = result['rag'] as Map<String, dynamic>;
        final qaHistory = ragState['qa_history'] as List<dynamic>;
        expect(qaHistory, hasLength(1));
        expect((qaHistory[0] as Map<String, dynamic>)['question'], 'Q1');
      });

      test('creates List when intermediate path uses "-" append syntax', () {
        final state = <String, dynamic>{};
        final operations = [
          {'op': 'add', 'path': '/data/items/-', 'value': 'first'},
        ];

        final result = applyJsonPatch(state, operations);

        final data = result['data'] as Map<String, dynamic>;
        final items = data['items'] as List<dynamic>;
        expect(items, ['first']);
      });
    });

    group('edge cases', () {
      test('handles empty path', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {'op': 'add', 'path': '', 'value': 'ignored'},
        ];

        final result = applyJsonPatch(state, operations);

        expect(result, equals({'key': 'value'}));
      });

      test('handles invalid array index beyond bounds', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/10', 'value': 'out of bounds'},
        ];

        // Should handle gracefully - either skip or extend
        final result = applyJsonPatch(state, operations);

        // Verify original items preserved
        final items = result['items'] as List;
        expect(items.contains('a'), isTrue);
        expect(items.contains('b'), isTrue);
      });

      test('handles negative array index', () {
        final state = <String, dynamic>{
          'items': ['a', 'b', 'c'],
        };
        final operations = [
          {'op': 'remove', 'path': '/items/-1'},
        ];

        // Should handle gracefully - skip invalid operation
        final result = applyJsonPatch(state, operations);

        // Original array should be unchanged since -1 is not a valid index
        expect(result['items'], ['a', 'b', 'c']);
      });

      test('handles non-numeric array index', () {
        final state = <String, dynamic>{
          'items': ['a', 'b'],
        };
        final operations = [
          {'op': 'add', 'path': '/items/notanumber', 'value': 'invalid'},
        ];

        // Should handle gracefully
        final result = applyJsonPatch(state, operations);

        // Array should be unchanged
        expect(result['items'], ['a', 'b']);
      });

      test('handles root path by replacing entire state', () {
        final state = <String, dynamic>{'key': 'value'};
        final operations = [
          {
            'op': 'replace',
            'path': '/',
            'value': {'new': 'state'},
          },
        ];

        final result = applyJsonPatch(state, operations);

        // Root path replacement replaces entire state
        expect(result, equals({'new': 'state'}));
      });

      test('handles complex nested structures', () {
        final state = <String, dynamic>{
          'rag': {
            'qa_history': <dynamic>[
              {'question': 'Q1', 'answer': 'A1', 'citations': <dynamic>[]},
            ],
          },
        };
        final operations = [
          {
            'op': 'add',
            'path': '/rag/qa_history/1',
            'value': {
              'question': 'Q2',
              'answer': 'A2',
              'citations': [
                {'chunk_id': 'c1', 'content': 'text'},
              ],
            },
          },
        ];

        final result = applyJsonPatch(state, operations);

        final haikuChat = result['rag'] as Map<String, dynamic>;
        final qaHistory = haikuChat['qa_history'] as List<dynamic>;
        expect(qaHistory, hasLength(2));
        final q2 = qaHistory[1] as Map<String, dynamic>;
        expect(q2['question'], 'Q2');
        expect(q2['citations'], hasLength(1));
      });
    });
  });
}
