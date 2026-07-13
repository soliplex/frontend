// ignore_for_file: prefer_const_constructors

import 'dart:convert';

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
    group('required constructor parameters', () {
      test('chunkId, content, documentId, documentUri are required', () {
        final citation = Citation(
          chunkId: 'chunk-123',
          content: 'content',
          documentId: 'doc-456',
          documentUri: 'https://example.com',
        );

        expect(citation.chunkId, equals('chunk-123'));
        expect(citation.content, equals('content'));
        expect(citation.documentId, equals('doc-456'));
        expect(citation.documentUri, equals('https://example.com'));
      });
    });

    group('optional fields', () {
      test('documentTitle, headings, index, pageNumbers default to null', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
        );

        expect(citation.documentTitle, isNull);
        expect(citation.headings, isNull);
        expect(citation.index, isNull);
        expect(citation.pageNumbers, isNull);
      });

      test('all optional fields can be provided', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'uri',
          documentTitle: 'Title',
          headings: ['Section 1'],
          index: 1,
          pageNumbers: [1, 2],
        );

        expect(citation.documentTitle, equals('Title'));
        expect(citation.headings, equals(['Section 1']));
        expect(citation.index, equals(1));
        expect(citation.pageNumbers, equals([1, 2]));
      });
    });

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
        expect(citation.chunkIds, equals(['c1', 'c2']));
        expect(citation.documentTitle, equals('Title'));
        expect(citation.headings, equals(['H1']));
        expect(citation.index, equals(5));
        expect(citation.pageNumbers, equals([1]));
        expect(citation.pictureRefs, equals(['#/pictures/0']));
      });

      test('toJson produces expected keys', () {
        final citation = Citation(
          chunkId: 'c1',
          content: 'text',
          documentId: 'd1',
          documentUri: 'uri',
        );

        final json = citation.toJson();
        expect(json.containsKey('chunk_id'), isTrue);
        expect(json.containsKey('chunk_ids'), isTrue);
        expect(json.containsKey('content'), isTrue);
        expect(json.containsKey('document_id'), isTrue);
        expect(json.containsKey('document_uri'), isTrue);
        expect(json.containsKey('picture_refs'), isTrue);
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

    group('roundtrip serialization', () {
      test('Citation survives JSON roundtrip', () {
        final original = Citation(
          chunkId: 'c1',
          content: 'content',
          documentId: 'd1',
          documentUri: 'https://example.com',
          documentTitle: 'Test Doc',
          index: 1,
          headings: ['Section 1'],
          pageNumbers: [1, 2],
          docItemRefs: ['#/texts/1'],
          pictureRefs: ['#/pictures/0'],
          chunkIds: ['c1', 'c2'],
        );

        final jsonString = jsonEncode(original.toJson());
        final decoded = Citation.fromJson(
          jsonDecode(jsonString) as Map<String, dynamic>,
        );

        expect(decoded.chunkId, equals(original.chunkId));
        expect(decoded.content, equals(original.content));
        expect(decoded.documentId, equals(original.documentId));
        expect(decoded.documentUri, equals(original.documentUri));
        expect(decoded.documentTitle, equals(original.documentTitle));
        expect(decoded.index, equals(original.index));
        expect(decoded.headings, equals(original.headings));
        expect(decoded.pageNumbers, equals(original.pageNumbers));
        expect(decoded.docItemRefs, equals(original.docItemRefs));
        expect(decoded.pictureRefs, equals(original.pictureRefs));
        expect(decoded.chunkIds, equals(original.chunkIds));
      });
    });
  });

  group('SearchResult contract', () {
    test('content and score are required; rest is optional', () {
      final result = SearchResult(content: 'found text', score: 0.85);

      expect(result.content, equals('found text'));
      expect(result.score, equals(0.85));
      expect(result.chunkId, isNull);
      expect(result.documentId, isNull);
      expect(result.documentUri, isNull);
      expect(result.documentTitle, isNull);
      expect(result.docItemRefs, isNull);
      expect(result.headings, isNull);
      expect(result.labels, isNull);
      expect(result.pageNumbers, isNull);
      expect(result.order, equals(0));
    });
  });
}
