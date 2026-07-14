import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/utils/parse_utils.dart';
import 'package:test/test.dart';

void main() {
  group('requireString', () {
    test('returns the value when it is a string', () {
      expect(requireString('hello', 'field'), equals('hello'));
    });

    test('throws MalformedResponseException when absent', () {
      expect(
        () => requireString(null, 'field'),
        throwsA(isA<MalformedResponseException>()),
      );
    });

    test('throws MalformedResponseException when wrong-typed', () {
      expect(
        () => requireString(42, 'field'),
        throwsA(isA<MalformedResponseException>()),
      );
    });
  });

  group('stringOrNull', () {
    test('returns the value when it is a string', () {
      expect(stringOrNull('hi', 'field'), equals('hi'));
    });

    test('returns null when absent', () {
      expect(stringOrNull(null, 'field'), isNull);
    });

    test('degrades a wrong-typed value to null', () {
      expect(stringOrNull(42, 'field'), isNull);
    });
  });

  group('intOrNull', () {
    test('returns the value when it is an int', () {
      expect(intOrNull(7, 'field'), equals(7));
    });

    test('returns null when absent', () {
      expect(intOrNull(null, 'field'), isNull);
    });

    test('degrades a wrong-typed value to null', () {
      expect(intOrNull('7', 'field'), isNull);
    });
  });

  group('stringList', () {
    test('returns an empty list when absent', () {
      expect(stringList(null, 'field'), isEmpty);
    });

    test('returns an empty list for a non-list value', () {
      expect(stringList('nope', 'field'), isEmpty);
    });

    test('keeps strings and drops non-string elements', () {
      expect(
        stringList(<Object?>['a', 1, 'b', null], 'field'),
        equals(['a', 'b']),
      );
    });
  });

  group('intList', () {
    test('returns an empty list when absent', () {
      expect(intList(null, 'field'), isEmpty);
    });

    test('returns an empty list for a non-list value', () {
      expect(intList(3, 'field'), isEmpty);
    });

    test('keeps ints and drops non-int elements', () {
      expect(
        intList(<Object?>[1, 'x', 2, null], 'field'),
        equals([1, 2]),
      );
    });
  });

  group('stringMap', () {
    test('returns an empty map when absent', () {
      expect(stringMap(null, 'field'), isEmpty);
    });

    test('returns an empty map for a non-map value', () {
      expect(stringMap(<Object?>['a'], 'field'), isEmpty);
    });

    test('keeps string→string entries and drops the rest', () {
      expect(
        stringMap(<Object?, Object?>{'a': '1', 'b': 2, 3: 'c'}, 'field'),
        equals({'a': '1'}),
      );
    });
  });
}
