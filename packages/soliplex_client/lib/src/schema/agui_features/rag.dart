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

import 'package:soliplex_client/src/utils/parse_utils.dart';

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
  final Map<String, dynamic> documentMeta;
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
    this.documentMeta = const {},
    this.documentTitle,
    required this.documentUri,
    this.headings,
    this.index,
    this.pageNumbers,
    this.pictureRefs,
  });

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
        chunkId: requireString(json["chunk_id"], "chunk_id"),
        chunkIds: stringList(json["chunk_ids"], "chunk_ids"),
        content: requireString(json["content"], "content"),
        docItemRefs: stringList(json["doc_item_refs"], "doc_item_refs"),
        documentId: requireString(json["document_id"], "document_id"),
        documentMeta: jsonMap(json["document_meta"], "document_meta"),
        documentTitle: stringOrNull(json["document_title"], "document_title"),
        documentUri: requireString(json["document_uri"], "document_uri"),
        headings: stringList(json["headings"], "headings"),
        index: intOrNull(json["index"], "index"),
        pageNumbers: intList(json["page_numbers"], "page_numbers"),
        pictureRefs: stringList(json["picture_refs"], "picture_refs"),
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
        "document_meta": documentMeta,
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

/// One row of a `searches` entry — a chunk from the stage-1 retrieval set,
/// cited or not.
///
/// Beyond the provenance a [Citation] already carries (document, headings,
/// page numbers, doc-item refs, `image_data`), a search result exposes
/// retrieval telemetry available *nowhere else* in the state:
///
/// - [score]: relevance score for the query.
/// - [order]: rank within the search.
/// - [labels]: backend classification tags.
///
/// The cited-figure path never builds a [SearchResult]; it reads `image_data`
/// + `document_id` straight off the raw row via [parseImageData]. This type is
/// retained as a value model for a future consumer of the `searches` retrieval
/// set; it carries no JSON parser — such a consumer builds it through a
/// resilient per-entry reader (as `RagSnapshot` does for [Citation]).
class SearchResult {
  final String? chunkId;
  final String content;
  final List<String>? docItemRefs;
  final String? documentId;
  final String? documentTitle;
  final String? documentUri;
  final List<String>? headings;
  final Map<String, String> imageData;
  final List<String>? labels;
  final int order;
  final List<int>? pageNumbers;
  final Map<String, String> pictureCaptions;
  final double score;

  SearchResult({
    this.chunkId,
    required this.content,
    this.docItemRefs,
    this.documentId,
    this.documentTitle,
    this.documentUri,
    this.headings,
    this.imageData = const {},
    this.labels,
    this.order = 0,
    this.pageNumbers,
    this.pictureCaptions = const {},
    required this.score,
  });

  /// Reads a raw `image_data` JSON value into a picture-ref → base64 map.
  /// Delegates to [stringMap]; see it for the shared parsing contract.
  static Map<String, String> parseImageData(Object? raw) =>
      stringMap(raw, 'image_data');

  /// Reads a raw `picture_captions` JSON value into a picture-ref → caption
  /// map. Delegates to [stringMap].
  static Map<String, String> parsePictureCaptions(Object? raw) =>
      stringMap(raw, 'picture_captions');
}
