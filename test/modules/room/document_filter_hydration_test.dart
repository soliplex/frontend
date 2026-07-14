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
}
