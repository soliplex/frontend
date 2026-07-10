// Generated code from quicktype - ignoring style issues
// ignore_for_file: sort_constructors_first
// ignore_for_file: prefer_single_quotes
// ignore_for_file: always_put_required_named_parameters_first
// ignore_for_file: argument_type_not_assignable
// ignore_for_file: unnecessary_ignore
// ignore_for_file: avoid_dynamic_calls
// ignore_for_file: inference_failure_on_untyped_parameter
// ignore_for_file: inference_failure_on_collection_literal

// To parse this JSON data, do
//
//     final rag = ragFromJson(jsonString);

import 'dart:convert';

Rag ragFromJson(String str) => Rag.fromJson(json.decode(str));

String ragToJson(Rag data) => json.encode(data.toJson());

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
        chunkId: json["chunk_id"],
        chunkIds: json["chunk_ids"] == null
            ? []
            : List<String>.from(json["chunk_ids"]!.map((x) => x)),
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
        index: json["index"],
        pageNumbers: json["page_numbers"] == null
            ? []
            : List<int>.from(json["page_numbers"]!.map((x) => x)),
        pictureRefs: json["picture_refs"] == null
            ? []
            : List<String>.from(json["picture_refs"]!.map((x) => x)),
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
        "labels":
            labels == null ? [] : List<dynamic>.from(labels!.map((x) => x)),
        "order": order,
        "page_numbers": pageNumbers == null
            ? []
            : List<dynamic>.from(pageNumbers!.map((x) => x)),
        "score": score,
      };
}
