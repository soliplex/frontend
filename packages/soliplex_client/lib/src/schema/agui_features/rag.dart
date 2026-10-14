// Dart mirror of haiku.rag's `Citation` schema type, and of the
// `ChunkMetadata` keys its `chunk_meta` map carries, holding the fields the
// frontend reads; `agui_feature_schema_drift_test.dart` lists the rest of
// `Citation`. The
// lint suppressions below keep the wire-oriented parsing and layout
// (double-quoted keys, field order, dynamic JSON access) of this schema
// mirror intact.
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
  final ChunkMetadata chunkMeta;
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
  final String? source;

  Citation({
    required this.chunkId,
    this.chunkMeta = const ChunkMetadata(),
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
    this.source,
  });

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
        chunkId: requireString(json["chunk_id"], "chunk_id"),
        chunkMeta: ChunkMetadata.fromJson(
          jsonMap(json["chunk_meta"], "chunk_meta"),
        ),
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
        source: stringOrNull(json["source"], "source"),
      );
}

///Two keys of the cited chunk's stored metadata, as haiku.rag's
///`ChunkMetadata` defines them; its `headings` and `labels` are not read.
///`chunk_meta` is the chunk's raw metadata, where chunks imported pre-built
///rather than chunked by haiku.rag may keep other keys or lack these. Empty
///when the citation does not report them.
class ChunkMetadata {
  final List<String> docItemRefs;
  final List<int> pageNumbers;

  const ChunkMetadata({
    this.docItemRefs = const [],
    this.pageNumbers = const [],
  });

  factory ChunkMetadata.fromJson(Map<String, dynamic> json) => ChunkMetadata(
        docItemRefs: stringList(
          json["doc_item_refs"],
          "chunk_meta.doc_item_refs",
        ),
        pageNumbers: intList(json["page_numbers"], "chunk_meta.page_numbers"),
      );
}
