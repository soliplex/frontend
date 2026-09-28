// ignore_for_file: prefer_const_constructors

import 'package:soliplex_client/src/errors/exceptions.dart';
import 'package:soliplex_client/src/schema/agui_features/rag.dart';
import 'package:test/test.dart';

/// Contract tests for the rag.dart schema types.
///
/// These tests document and enforce the API surface that consuming code depends
/// on. They will fail to compile if required fields are renamed or removed,
/// alerting us to update consuming code. They also pin the parsing resilience
/// contract: a malformed optional field degrades to its default without taking
/// down the rest of the object.
void main() {
  group('Citation contract', () {
    group('JSON keys', () {
      test('snake_case keys match backend', () {
        final json = {
          'chunk_id': 'c1',
          'chunk_ids': ['c1', 'c2'],
          'content': 'text',
          'document_id': 'd1',
          'document_uri': 'uri',
          'document_title': 'Title',
          'headings': ['H1'],
          'index': 5,
          'page_numbers': [1],
          'picture_refs': ['#/pictures/0'],
        };

        final citation = Citation.fromJson(json);
        expect(citation.chunkId, equals('c1'));
        expect(citation.documentTitle, equals('Title'));
        expect(citation.headings, equals(['H1']));
        expect(citation.index, equals(5));
        expect(citation.pageNumbers, equals([1]));
        expect(citation.pictureRefs, equals(['#/pictures/0']));
      });

      test('document_meta parses into a map, defaulting to empty when absent',
          () {
        final withMeta = Citation.fromJson({
          'chunk_id': 'c1',
          'content': 'text',
          'document_id': 'd1',
          'document_uri': 'uri',
          'document_meta': {'source_url': 'https://example.test/a'},
        });
        expect(
          withMeta.documentMeta['source_url'],
          equals('https://example.test/a'),
        );

        final withoutMeta = Citation.fromJson({
          'chunk_id': 'c1',
          'content': 'text',
          'document_id': 'd1',
          'document_uri': 'uri',
        });
        expect(withoutMeta.documentMeta, isEmpty);
      });
    });

    group('malformed-field resilience', () {
      Map<String, dynamic> validBase() => {
            'chunk_id': 'c1',
            'content': 'text',
            'document_id': 'd1',
            'document_uri': 'uri',
          };

      test('malformed picture_refs degrades to empty, other fields survive',
          () {
        final citation = Citation.fromJson({
          ...validBase(),
          'picture_refs': 'not-a-list',
        });

        expect(citation.pictureRefs, isEmpty);
        expect(citation.content, equals('text'));
        expect(citation.documentId, equals('d1'));
      });

      test('picture_refs drops non-string elements, keeps the valid ones', () {
        final citation = Citation.fromJson({
          ...validBase(),
          'picture_refs': ['#/pictures/0', 123, '#/pictures/1'],
        });

        expect(citation.pictureRefs, equals(['#/pictures/0', '#/pictures/1']));
      });

      test('page_numbers drops non-int elements', () {
        final citation = Citation.fromJson({
          ...validBase(),
          'page_numbers': [1, 'two', 3],
        });

        expect(citation.pageNumbers, equals([1, 3]));
      });

      test('malformed optional scalar degrades to null', () {
        final citation = Citation.fromJson({
          ...validBase(),
          'index': 'not-an-int',
          'document_title': 42,
        });

        expect(citation.index, isNull);
        expect(citation.documentTitle, isNull);
        expect(citation.content, equals('text'));
      });

      test('malformed required field still throws (entry is dropped)', () {
        expect(
          () => Citation.fromJson({
            'chunk_id': 'c1',
            'content': 42,
            'document_id': 'd1',
            'document_uri': 'uri',
          }),
          throwsA(isA<MalformedResponseException>()),
        );
      });
    });
  });
}
