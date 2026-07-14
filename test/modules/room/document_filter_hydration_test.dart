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
      final resolved = <Set<RagDocument>>[];
      DocumentFilterHydrator(onResolved: resolved.add)
        ..setCorpus(corpus)
        ..beginThread()
        ..setFilter("id = 'a'");
      expect(resolved, hasLength(1));
      expect(resolved.single.single.id, equals('a'));
    });

    test('resolves when filter arrives before corpus', () {
      final resolved = <Set<RagDocument>>[];
      DocumentFilterHydrator(onResolved: resolved.add)
        ..beginThread()
        ..setFilter("id = 'b'")
        ..setCorpus(corpus);
      expect(resolved.single.single.id, equals('b'));
    });

    test('does not resolve with only one input', () {
      final resolved = <Set<RagDocument>>[];
      DocumentFilterHydrator(onResolved: resolved.add).setCorpus(corpus);
      expect(resolved, isEmpty);
    });

    test('resolves a null filter to an empty selection', () {
      final resolved = <Set<RagDocument>>[];
      DocumentFilterHydrator(onResolved: resolved.add)
        ..setCorpus(corpus)
        ..beginThread()
        ..setFilter(null);
      expect(resolved, hasLength(1));
      expect(resolved.single, isEmpty);
    });

    test('resolves only once even if the filter is set twice', () {
      final resolved = <Set<RagDocument>>[];
      DocumentFilterHydrator(onResolved: resolved.add)
        ..setCorpus(corpus)
        ..beginThread()
        ..setFilter("id = 'a'")
        ..setFilter("id = 'b'");
      expect(resolved, hasLength(1));
    });

    test('beginThread lets a new thread resolve with the retained corpus', () {
      final resolved = <Set<RagDocument>>[];
      final hydrator = DocumentFilterHydrator(onResolved: resolved.add)
        ..setCorpus(corpus)
        ..beginThread()
        ..setFilter("id = 'a'");
      hydrator
        ..beginThread()
        ..setFilter("id = 'b'");
      expect(resolved, hasLength(2));
      expect(resolved.last.single.id, equals('b'));
    });
  });
}
