import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/lobby/thread_query.dart';

void main() {
  group('parseThreadQuery', () {
    test('returns an empty query for empty input', () {
      final query = parseThreadQuery('');

      expect(query.text, isEmpty);
      expect(query.labelNames, isEmpty);
      expect(query.isEmpty, isTrue);
    });

    test('treats input with no tokens as pure text', () {
      final query = parseThreadQuery('Osprey Pilot Manual');

      expect(query.text, equals('Osprey Pilot Manual'));
      expect(query.labelNames, isEmpty);
    });

    test('treats input with only tokens as pure labels', () {
      final query = parseThreadQuery('@manuals @v22osprey');

      expect(query.text, isEmpty);
      expect(query.labelNames, equals(['manuals', 'v22osprey']));
    });

    test('splits text and labels when both are present', () {
      final query = parseThreadQuery('Osprey Manual @manuals');

      expect(query.text, equals('Osprey Manual'));
      expect(query.labelNames, equals(['manuals']));
    });

    test('handles a token in the middle without welding words together', () {
      // Removing the token outright would produce "OspreyManual".
      final query = parseThreadQuery('Osprey @manuals Manual');

      expect(query.text, equals('Osprey Manual'));
      expect(query.labelNames, equals(['manuals']));
    });

    test('lower-cases label names', () {
      // Label names ignore case server-side; leaving the case alone
      // would make '@Urgent' quietly match nothing.
      final query = parseThreadQuery('@Urgent @MANUALS');

      expect(query.labelNames, equals(['urgent', 'manuals']));
    });

    test('collapses duplicate labels, keeping first-seen order', () {
      final query = parseThreadQuery('@urgent @manuals @Urgent');

      expect(query.labelNames, equals(['urgent', 'manuals']));
    });

    test('ends a token at a comma or semicolon', () {
      final query = parseThreadQuery('@urgent, @manuals; tail');

      expect(query.labelNames, equals(['urgent', 'manuals']));
      // The separators are not part of the names, and survive as text.
      expect(query.text, equals(', ; tail'));
    });

    test('leaves a bare @ as text rather than an empty label', () {
      // This is what the user has typed the instant the autocomplete
      // opens; an empty name would filter to nothing.
      final query = parseThreadQuery('Osprey @');

      expect(query.labelNames, isEmpty);
      expect(query.text, equals('Osprey @'));
    });

    test('collapses runs of whitespace in the remaining text', () {
      final query = parseThreadQuery('  Osprey   @manuals    Manual  ');

      expect(query.text, equals('Osprey Manual'));
    });

    test('keeps an @ inside a word as part of a token', () {
      // Deliberate: names may contain punctuation, and there is no
      // email-like case in a thread search worth special-casing.
      final query = parseThreadQuery('a@b');

      expect(query.labelNames, equals(['b']));
      expect(query.text, equals('a'));
    });

    test('value equality ignores identity', () {
      expect(
        parseThreadQuery('Osprey @manuals'),
        equals(parseThreadQuery('Osprey @manuals')),
      );
      expect(
        parseThreadQuery('Osprey @manuals'),
        isNot(equals(parseThreadQuery('Osprey @urgent'))),
      );
    });
  });

  group('activeLabelToken', () {
    test('returns the token being typed', () {
      const raw = 'Osprey @man';

      expect(activeLabelToken(raw, raw.length), equals('man'));
    });

    test('returns an empty string for a bare @', () {
      // A real state, not "no token": the menu is open and should be
      // showing every label.
      const raw = 'Osprey @';

      expect(activeLabelToken(raw, raw.length), equals(''));
    });

    test('returns null when there is no @ at all', () {
      expect(activeLabelToken('Osprey', 6), isNull);
    });

    test('returns null once whitespace ends the token', () {
      // This is what closes the menu.
      const raw = 'Osprey @manuals ';

      expect(activeLabelToken(raw, raw.length), isNull);
    });

    test('returns null once punctuation ends the token', () {
      const raw = 'Osprey @manuals,';

      expect(activeLabelToken(raw, raw.length), isNull);
    });

    test('reads the token at the cursor, not at the end of the line', () {
      // Editing mid-string must not complete against the wrong token.
      const raw = '@man tail';

      expect(activeLabelToken(raw, 4), equals('man'));
    });

    test('lower-cases the token', () {
      const raw = '@MAN';

      expect(activeLabelToken(raw, raw.length), equals('man'));
    });

    test('returns null for an out-of-range cursor', () {
      expect(activeLabelToken('@man', 99), isNull);
      expect(activeLabelToken('@man', -1), isNull);
    });
  });

  group('completeLabelToken', () {
    test('replaces the in-progress token and leaves a trailing space', () {
      const raw = 'Osprey @man';

      final completed = completeLabelToken(raw, raw.length, 'manuals');

      expect(completed?.text, equals('Osprey @manuals '));
      // Cursor lands past the space, so typing continues naturally.
      expect(completed?.cursor, equals('Osprey @manuals '.length));
    });

    test('completes a bare @', () {
      const raw = '@';

      final completed = completeLabelToken(raw, raw.length, 'urgent');

      expect(completed?.text, equals('@urgent '));
    });

    test('keeps the text after the cursor', () {
      const raw = '@man tail';

      final completed = completeLabelToken(raw, 4, 'manuals');

      expect(completed?.text, equals('@manuals  tail'));
      expect(completed?.cursor, equals('@manuals '.length));
    });

    test('returns null when there is nothing to complete', () {
      expect(completeLabelToken('Osprey', 6, 'manuals'), isNull);
      expect(completeLabelToken('Osprey @manuals ', 16, 'urgent'), isNull);
    });
  });
}
