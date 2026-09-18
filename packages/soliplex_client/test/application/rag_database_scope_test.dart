import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

Room _room(Map<String, RoomSkill> skills) => Room(
      id: 'r',
      name: 'Room',
      skills: skills,
    );

RoomSkill _skill(
  String name, {
  String? namespace,
  Object? databaseNames,
}) =>
    RoomSkill(
      name: name,
      description: '',
      stateNamespace: namespace,
      extraParameters: {
        if (databaseNames != null) 'database_names': databaseNames,
      },
    );

void main() {
  group('RagDatabaseScope.of', () {
    test('is none for a room with no skills', () {
      expect(RagDatabaseScope.of(_room({})), equals(RagDatabaseScope.none));
      expect(RagDatabaseScope.none.isSelectable, isFalse);
    });

    test('reads one skill database names and namespace', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill('rag', namespace: 'rag', databaseNames: ['a', 'b']),
        }),
      );
      expect(scope.names, equals(['a', 'b']));
      expect(scope.namespaces, equals(['rag']));
      expect(scope.isSelectable, isTrue);
    });

    test('a single database is not selectable', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill('rag', namespace: 'rag', databaseNames: ['only']),
        }),
      );
      expect(scope.names, equals(['only']));
      expect(scope.isSelectable, isFalse);
    });

    test('unions names across skills in first-seen order, without repeats', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill('rag', namespace: 'rag', databaseNames: ['a', 'b']),
          'rag-analysis': _skill(
            'rag-analysis',
            namespace: 'analysis',
            databaseNames: ['b', 'c'],
          ),
        }),
      );
      expect(scope.names, equals(['a', 'b', 'c']));
      expect(scope.namespaces, equals(['rag', 'analysis']));
    });

    test('ignores a skill without a state namespace', () {
      final scope = RagDatabaseScope.of(
        _room({
          'stateless': _skill('stateless', databaseNames: ['a', 'b']),
        }),
      );
      expect(scope, equals(RagDatabaseScope.none));
    });

    test('ignores a skill naming no database', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill('rag', namespace: 'rag', databaseNames: ['a', 'b']),
          'policy': _skill('policy', namespace: 'citation_policy'),
        }),
      );
      expect(scope.namespaces, equals(['rag']));
    });

    test('keeps what can be read of a malformed list', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill(
            'rag',
            namespace: 'rag',
            databaseNames: ['a', 1, '', null, 'b'],
          ),
          'other': _skill('other', namespace: 'analysis', databaseNames: 'a'),
        }),
      );
      expect(scope.names, equals(['a', 'b']));
      expect(scope.namespaces, equals(['rag']));
    });

    test('sets a name the backend marked missing apart', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill(
            'rag',
            namespace: 'rag',
            databaseNames: ['papers', 'MISSING: wiki', 'MISSING: '],
          ),
        }),
      );
      expect(scope.names, equals(['papers']));
      expect(scope.missing, equals(['wiki']));
      expect(scope.isSelectable, isFalse);
    });

    test('a room whose every database is missing is not none', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill(
            'rag',
            namespace: 'rag',
            databaseNames: ['MISSING: papers'],
          ),
        }),
      );
      expect(scope, isNot(equals(RagDatabaseScope.none)));
      expect(scope.names, isEmpty);
      expect(scope.missing, equals(['papers']));
      expect(scope.namespaces, equals(['rag']));
    });

    test('equality is by value', () {
      final a = RagDatabaseScope(names: const ['x'], namespaces: const ['rag']);
      final b = RagDatabaseScope(names: const ['x'], namespaces: const ['rag']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(
        a,
        isNot(
          equals(
            RagDatabaseScope(names: const ['y'], namespaces: const ['rag']),
          ),
        ),
      );
    });

    test('lists are unmodifiable', () {
      final scope = RagDatabaseScope.of(
        _room({
          'rag': _skill('rag', namespace: 'rag', databaseNames: ['a', 'b']),
        }),
      );
      expect(() => scope.names.add('c'), throwsUnsupportedError);
      expect(() => scope.namespaces.add('x'), throwsUnsupportedError);
    });
  });
}
