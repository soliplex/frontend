import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/document_filter_hydration.dart';

void main() {
  group('resolveSelectionFromFilter', () {
    const corpus = {
      'a': RagDocument(id: 'a', title: 'Alpha'),
      'b': RagDocument(id: 'b', title: 'Beta'),
    };

    test('resolves ids to their corpus documents', () {
      final selection = resolveSelectionFromFilter("id IN ('a', 'b')", corpus);
      expect(selection, contains(const RagDocument(id: 'a', title: 'Alpha')));
      expect(
        selection.firstWhere((d) => d.id == 'b').title,
        equals('Beta'),
      );
    });

    test('keeps an unresolved id as an unavailable placeholder', () {
      final selection = resolveSelectionFromFilter("id = 'gone'", corpus);
      final doc = selection.single;
      expect(doc.id, equals('gone'));
      expect(doc.title, equals(unavailableDocumentTitle));
    });

    test('null filter yields an empty selection', () {
      expect(resolveSelectionFromFilter(null, corpus), isEmpty);
    });

    test('empty filter string yields an empty selection', () {
      expect(resolveSelectionFromFilter('', corpus), isEmpty);
    });
  });

  group('DocumentFilterHydrator', () {
    const corpus = [
      RagDocument(id: 'a', title: 'Alpha'),
      RagDocument(id: 'b', title: 'Beta'),
    ];

    test('resolves once when corpus arrives before filter', () {
      final resolved = <({String threadId, Set<RagDocument> selection})>[];
      DocumentFilterHydrator(
        onResolved: (t, s) => resolved.add((threadId: t, selection: s)),
      )
        ..setCorpus(corpus)
        ..setFilter('t1', "id = 'a'");
      expect(resolved, hasLength(1));
      expect(resolved.single.threadId, equals('t1'));
      expect(resolved.single.selection.single.id, equals('a'));
    });

    test('resolves when filter arrives before corpus', () {
      final resolved = <({String threadId, Set<RagDocument> selection})>[];
      DocumentFilterHydrator(
        onResolved: (t, s) => resolved.add((threadId: t, selection: s)),
      )
        ..setFilter('t1', "id = 'b'")
        ..setCorpus(corpus);
      expect(resolved.single.threadId, equals('t1'));
      expect(resolved.single.selection.single.id, equals('b'));
    });

    test('does not resolve with only corpus (no filter)', () {
      final resolved = <({String threadId, Set<RagDocument> selection})>[];
      DocumentFilterHydrator(
        onResolved: (t, s) => resolved.add((threadId: t, selection: s)),
      ).setCorpus(corpus);
      expect(resolved, isEmpty);
    });

    test('does not resolve with only filter (no corpus)', () {
      final resolved = <({String threadId, Set<RagDocument> selection})>[];
      DocumentFilterHydrator(
        onResolved: (t, s) => resolved.add((threadId: t, selection: s)),
      ).setFilter('t1', "id = 'a'");
      expect(resolved, isEmpty);
    });

    test('resolves a null filter to an empty selection', () {
      final resolved = <({String threadId, Set<RagDocument> selection})>[];
      DocumentFilterHydrator(
        onResolved: (t, s) => resolved.add((threadId: t, selection: s)),
      )
        ..setCorpus(corpus)
        ..setFilter('t1', null);
      expect(resolved, hasLength(1));
      expect(resolved.single.selection, isEmpty);
    });

    test('resolves only once for the same thread', () {
      final resolved = <({String threadId, Set<RagDocument> selection})>[];
      DocumentFilterHydrator(
        onResolved: (t, s) => resolved.add((threadId: t, selection: s)),
      )
        ..setCorpus(corpus)
        ..setFilter('t1', "id = 'a'")
        ..setFilter('t1', "id = 'b'");
      expect(resolved, hasLength(1));
    });

    test('switching thread re-resolves with the retained corpus', () {
      final resolved = <({String threadId, Set<RagDocument> selection})>[];
      DocumentFilterHydrator(
        onResolved: (t, s) => resolved.add((threadId: t, selection: s)),
      )
        ..setCorpus(corpus)
        ..setFilter('t1', "id = 'a'")
        ..setFilter('t2', "id = 'b'");
      expect(resolved, hasLength(2));
      expect(resolved.last.threadId, equals('t2'));
      expect(resolved.last.selection.single.id, equals('b'));
    });
  });

  group('shouldApplyHydratedSelection', () {
    test(
        'applies for the active thread with a non-empty result and empty store',
        () {
      expect(
        shouldApplyHydratedSelection(
          resolvedThreadId: 't1',
          activeThreadId: 't1',
          resolvedSelectionIsEmpty: false,
          currentSelectionIsEmpty: true,
        ),
        isTrue,
      );
    });

    test('rejects when the resolution is for a different thread', () {
      expect(
        shouldApplyHydratedSelection(
          resolvedThreadId: 't1',
          activeThreadId: 't2',
          resolvedSelectionIsEmpty: false,
          currentSelectionIsEmpty: true,
        ),
        isFalse,
      );
    });

    test('rejects when no thread is active', () {
      expect(
        shouldApplyHydratedSelection(
          resolvedThreadId: 't1',
          activeThreadId: null,
          resolvedSelectionIsEmpty: false,
          currentSelectionIsEmpty: true,
        ),
        isFalse,
      );
    });

    test('rejects an empty resolved selection', () {
      expect(
        shouldApplyHydratedSelection(
          resolvedThreadId: 't1',
          activeThreadId: 't1',
          resolvedSelectionIsEmpty: true,
          currentSelectionIsEmpty: true,
        ),
        isFalse,
      );
    });

    test('rejects when the user already has a selection (local edit wins)', () {
      expect(
        shouldApplyHydratedSelection(
          resolvedThreadId: 't1',
          activeThreadId: 't1',
          resolvedSelectionIsEmpty: false,
          currentSelectionIsEmpty: false,
        ),
        isFalse,
      );
    });
  });
}
