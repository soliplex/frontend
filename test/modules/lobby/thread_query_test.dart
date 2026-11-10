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
      final query = parseThreadQuery('Harbor Pilot Manual');

      expect(query.text, equals('Harbor Pilot Manual'));
      expect(query.labelNames, isEmpty);
    });

    test('treats input with only tokens as pure labels', () {
      final query = parseThreadQuery('@manuals @q4roadmap');

      expect(query.text, isEmpty);
      expect(query.labelNames, equals(['manuals', 'q4roadmap']));
    });

    test('splits text and labels when both are present', () {
      final query = parseThreadQuery('Harbor Manual @manuals');

      expect(query.text, equals('Harbor Manual'));
      expect(query.labelNames, equals(['manuals']));
    });

    test('reads @no-label as unlabeled rather than as a label', () {
      final query = parseThreadQuery('Manual @No-Label @urgent');

      expect(query.text, equals('Manual'));
      expect(query.labelNames, equals(['urgent']));
      expect(query.unlabeled, isTrue);
      expect(query.isEmpty, isFalse);
      expect(query, isNot(equals(parseThreadQuery('Manual @urgent'))));
    });

    test('reserves the no-label name whatever its case', () {
      expect(isReservedLabelName(' No-Label '), isTrue);
      expect(isReservedLabelName('no labels'), isFalse);
    });

    test('handles a token in the middle without welding words together', () {
      // Removing the token outright would produce "HarborManual".
      final query = parseThreadQuery('Harbor @manuals Manual');

      expect(query.text, equals('Harbor Manual'));
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
      final query = parseThreadQuery('Harbor @');

      expect(query.labelNames, isEmpty);
      expect(query.text, equals('Harbor @'));
    });

    test('collapses runs of whitespace in the remaining text', () {
      final query = parseThreadQuery('  Harbor   @manuals    Manual  ');

      expect(query.text, equals('Harbor Manual'));
    });

    test('reads a quoted token as one name', () {
      // Label names may contain spaces — "Q4 Roadmap" is ordinary — and
      // an unquoted token would end mid-name, leaving the remainder to
      // become free text.
      final query = parseThreadQuery('@"Q4 Roadmap" manual');

      expect(query.labelNames, equals(['q4 roadmap']));
      expect(query.text, equals('manual'));
    });

    test('mixes quoted and bare tokens', () {
      final query = parseThreadQuery('@urgent @"Q4 Roadmap"');

      expect(query.labelNames, equals(['urgent', 'q4 roadmap']));
      expect(query.text, isEmpty);
    });

    test('ignores an empty quoted token', () {
      // '@""' names nothing; filtering on a label that cannot exist
      // would empty the list for no stated reason.
      final query = parseThreadQuery('@"" tail');

      expect(query.labelNames, isEmpty);
      expect(query.text, equals('tail'));
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
        parseThreadQuery('Harbor @manuals'),
        equals(parseThreadQuery('Harbor @manuals')),
      );
      expect(
        parseThreadQuery('Harbor @manuals'),
        isNot(equals(parseThreadQuery('Harbor @urgent'))),
      );
    });
  });

  group('activeLabelToken', () {
    test('returns the token being typed', () {
      const raw = 'Harbor @man';

      expect(activeLabelToken(raw, raw.length), equals('man'));
    });

    test('returns an empty string for a bare @', () {
      // A real state, not "no token": the menu is open and should be
      // showing every label.
      const raw = 'Harbor @';

      expect(activeLabelToken(raw, raw.length), equals(''));
    });

    test('returns null when there is no @ at all', () {
      expect(activeLabelToken('Harbor', 6), isNull);
    });

    test('returns null once whitespace ends the token', () {
      // This is what closes the menu.
      const raw = 'Harbor @manuals ';

      expect(activeLabelToken(raw, raw.length), isNull);
    });

    test('returns null once punctuation ends the token', () {
      const raw = 'Harbor @manuals,';

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

    test('keeps reading a quoted token across its spaces', () {
      // The menu has to stay open while a multi-word name is typed.
      const raw = '@"Q4 Road';

      expect(activeLabelToken(raw, raw.length), equals('q4 road'));
    });

    test('returns null once the closing quote lands', () {
      const raw = '@"Q4 Roadmap"';

      expect(activeLabelToken(raw, raw.length), isNull);
    });
  });

  group('completeLabelToken', () {
    test('replaces the in-progress token and leaves a trailing space', () {
      const raw = 'Harbor @man';

      final completed = completeLabelToken(raw, raw.length, 'manuals');

      expect(completed?.text, equals('Harbor @manuals '));
      // Cursor lands past the space, so typing continues naturally.
      expect(completed?.cursor, equals('Harbor @manuals '.length));
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
      expect(completeLabelToken('Harbor', 6, 'manuals'), isNull);
      expect(completeLabelToken('Harbor @manuals ', 16, 'urgent'), isNull);
    });

    test('quotes a name that contains spaces', () {
      const raw = '@q4';

      final completed = completeLabelToken(raw, raw.length, 'q4 roadmap');

      // Unquoted this would round-trip as label "q4" plus the word
      // "roadmap" — a different query from the one the user picked.
      expect(completed?.text, equals('@"q4 roadmap" '));
      expect(
        parseThreadQuery(completed!.text).labelNames,
        equals(['q4 roadmap']),
      );
    });

    test('completes a quoted token in progress', () {
      const raw = '@"q4 road';

      final completed = completeLabelToken(raw, raw.length, 'q4 roadmap');

      expect(completed?.text, equals('@"q4 roadmap" '));
    });
  });

  group('formatLabelToken', () {
    test('leaves a simple name bare', () {
      expect(formatLabelToken('urgent'), equals('@urgent'));
    });

    test('quotes anything the parser would otherwise split', () {
      expect(formatLabelToken('q4 roadmap'), equals('@"q4 roadmap"'));
      expect(formatLabelToken('a,b'), equals('@"a,b"'));
    });
  });
}
