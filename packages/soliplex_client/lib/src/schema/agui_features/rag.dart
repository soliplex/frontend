// Dart types mirroring the backend haiku.rag `rag` namespace schema. The
// lint suppressions below keep the wire-oriented parsing and layout
// (double-quoted keys, field order, dynamic JSON access) of these schema
// mirrors intact.
// ignore_for_file: sort_constructors_first
// ignore_for_file: prefer_single_quotes
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: argument_type_not_assignable
// ignore_for_file: unnecessary_ignore
// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: inference_failure_on_untyped_parameter
// ignore_for_file: inference_failure_on_collection_literal

import 'dart:developer' as developer;

import 'package:soliplex_client/src/errors/exceptions.dart';

class Rag {
  final Map<String, Citation>? citationIndex;
  final List<String>? citations;
  final String? documentFilter;
  final Map<String, List<SearchResult>>? searches;

  Rag({
    this.citationIndex,
    this.citations,
    this.documentFilter,
    this.searches,
  });

  factory Rag.fromJson(Map<String, dynamic> json) => Rag(
        citationIndex: json["citation_index"] == null
            ? {}
            : Map<String, Citation>.from(
                Map.from(json["citation_index"]!).map(
                  (k, v) => MapEntry<String, Citation>(k, Citation.fromJson(v)),
                ),
              ),
        citations: json["citations"] == null
            ? []
            : List<String>.from(json["citations"]!.map((x) => x)),
        documentFilter: json["document_filter"],
        searches: json["searches"] == null
            ? null
            : Map.from(json["searches"]!).map(
                (k, v) => MapEntry<String, List<SearchResult>>(
                  k,
                  List<SearchResult>.from(
                    v.map((x) => SearchResult.fromJson(x)),
                  ),
                ),
              ),
      );

  Map<String, dynamic> toJson() => {
        "citation_index": citationIndex == null
            ? {}
            : Map.from(citationIndex!).map(
                (k, v) => MapEntry<String, dynamic>(k, v.toJson()),
              ),
        "citations": citations == null
            ? []
            : List<dynamic>.from(citations!.map((x) => x)),
        "document_filter": documentFilter,
        "searches": searches == null
            ? null
            : Map.from(searches!).map(
                (k, v) => MapEntry<String, dynamic>(
                  k,
                  List<dynamic>.from(v.map((x) => x.toJson())),
                ),
              ),
      };
}

/// A required string field: throws [MalformedResponseException] when absent
/// or not a string, so the caller can drop just this entry (its siblings are
/// parsed independently) instead of the whole batch.
String _requiredString(dynamic value, String field) {
  if (value is String) return value;
  throw MalformedResponseException(
    message: 'Citation field "$field" must be a string, '
        'got ${value.runtimeType}',
  );
}

void _logDropped(String message) => developer.log(
      message,
      name: 'soliplex_client.rag',
      level: 900,
    );

/// An optional string field: a present-but-wrong-typed value degrades to null
/// (logged) rather than throwing, so one malformed field never takes down the
/// rest of the object. An absent field is normal and silent.
String? _stringOrNull(dynamic value, String field) {
  if (value == null || value is String) return value as String?;
  _logDropped('Citation field "$field": expected string, '
      'got ${value.runtimeType}; dropped.');
  return null;
}

/// An optional int field: a present-but-wrong-typed value degrades to null
/// (logged). An absent field is normal and silent.
int? _intOrNull(dynamic value, String field) {
  if (value == null || value is int) return value as int?;
  _logDropped('Citation field "$field": expected int, '
      'got ${value.runtimeType}; dropped.');
  return null;
}

/// An optional list-of-strings field: a present-but-non-list degrades to empty
/// and any non-string element is dropped, isolating malformed input to this
/// field. Both cases are logged; an absent field is normal and silent.
List<String> _stringList(dynamic value, String field) {
  if (value == null) return const [];
  if (value is! List) {
    _logDropped('Citation field "$field": expected list, '
        'got ${value.runtimeType}; using empty.');
    return const [];
  }
  final result = value.whereType<String>().toList();
  if (result.length != value.length) {
    _logDropped('Citation field "$field": dropped '
        '${value.length - result.length} non-string element(s).');
  }
  return result;
}

/// An optional list-of-ints field: a present-but-non-list degrades to empty and
/// any non-int element is dropped. Both cases are logged; an absent field is
/// normal and silent.
List<int> _intList(dynamic value, String field) {
  if (value == null) return const [];
  if (value is! List) {
    _logDropped('Citation field "$field": expected list, '
        'got ${value.runtimeType}; using empty.');
    return const [];
  }
  final result = value.whereType<int>().toList();
  if (result.length != value.length) {
    _logDropped('Citation field "$field": dropped '
        '${value.length - result.length} non-int element(s).');
  }
  return result;
}

///Resolved citation with full metadata for display/visual grounding.
///
///Used by research graph and chat applications. The optional index field
///supports UI display ordering in chat contexts.
class Citation {
  final String chunkId;
  final List<String>? chunkIds;
  final String content;
  final List<String>? docItemRefs;
  final String documentId;
  final String? documentTitle;
  final String documentUri;
  final List<String>? headings;
  final int? index;
  final List<int>? pageNumbers;
  final List<String>? pictureRefs;

  Citation({
    required this.chunkId,
    this.chunkIds,
    required this.content,
    this.docItemRefs,
    required this.documentId,
    this.documentTitle,
    required this.documentUri,
    this.headings,
    this.index,
    this.pageNumbers,
    this.pictureRefs,
  });

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
        chunkId: _requiredString(json["chunk_id"], "chunk_id"),
        chunkIds: _stringList(json["chunk_ids"], "chunk_ids"),
        content: _requiredString(json["content"], "content"),
        docItemRefs: _stringList(json["doc_item_refs"], "doc_item_refs"),
        documentId: _requiredString(json["document_id"], "document_id"),
        documentTitle: _stringOrNull(json["document_title"], "document_title"),
        documentUri: _requiredString(json["document_uri"], "document_uri"),
        headings: _stringList(json["headings"], "headings"),
        index: _intOrNull(json["index"], "index"),
        pageNumbers: _intList(json["page_numbers"], "page_numbers"),
        pictureRefs: _stringList(json["picture_refs"], "picture_refs"),
      );

  Map<String, dynamic> toJson() => {
        "chunk_id": chunkId,
        "chunk_ids":
            chunkIds == null ? [] : List<dynamic>.from(chunkIds!.map((x) => x)),
        "content": content,
        "doc_item_refs": docItemRefs == null
            ? []
            : List<dynamic>.from(docItemRefs!.map((x) => x)),
        "document_id": documentId,
        "document_title": documentTitle,
        "document_uri": documentUri,
        "headings":
            headings == null ? [] : List<dynamic>.from(headings!.map((x) => x)),
        "index": index,
        "page_numbers": pageNumbers == null
            ? []
            : List<dynamic>.from(pageNumbers!.map((x) => x)),
        "picture_refs": pictureRefs == null
            ? []
            : List<dynamic>.from(pictureRefs!.map((x) => x)),
      };
}

///Search result with optional provenance information for citations.
class SearchResult {
  final String? chunkId;
  final String content;
  final List<String>? docItemRefs;
  final String? documentId;
  final String? documentTitle;
  final String? documentUri;
  final List<String>? headings;
  final Map<String, String>? imageData;
  final List<String>? labels;
  final int order;
  final List<int>? pageNumbers;
  final double score;

  SearchResult({
    this.chunkId,
    required this.content,
    this.docItemRefs,
    this.documentId,
    this.documentTitle,
    this.documentUri,
    this.headings,
    this.imageData,
    this.labels,
    this.order = 0,
    this.pageNumbers,
    required this.score,
  });

  factory SearchResult.fromJson(Map<String, dynamic> json) => SearchResult(
        chunkId: json["chunk_id"],
        content: json["content"],
        docItemRefs: json["doc_item_refs"] == null
            ? []
            : List<String>.from(json["doc_item_refs"]!.map((x) => x)),
        documentId: json["document_id"],
        documentTitle: json["document_title"],
        documentUri: json["document_uri"],
        headings: json["headings"] == null
            ? []
            : List<String>.from(json["headings"]!.map((x) => x)),
        imageData: json["image_data"] == null
            ? null
            : Map<String, String>.from(json["image_data"]!),
        labels: json["labels"] == null
            ? []
            : List<String>.from(json["labels"]!.map((x) => x)),
        order: json["order"] ?? 0,
        pageNumbers: json["page_numbers"] == null
            ? []
            : List<int>.from(json["page_numbers"]!.map((x) => x)),
        score: json["score"]?.toDouble(),
      );

  Map<String, dynamic> toJson() => {
        "chunk_id": chunkId,
        "content": content,
        "doc_item_refs": docItemRefs == null
            ? []
            : List<dynamic>.from(docItemRefs!.map((x) => x)),
        "document_id": documentId,
        "document_title": documentTitle,
        "document_uri": documentUri,
        "headings":
            headings == null ? [] : List<dynamic>.from(headings!.map((x) => x)),
        "image_data": imageData,
        "labels":
            labels == null ? [] : List<dynamic>.from(labels!.map((x) => x)),
        "order": order,
        "page_numbers": pageNumbers == null
            ? []
            : List<dynamic>.from(pageNumbers!.map((x) => x)),
        "score": score,
      };
}
