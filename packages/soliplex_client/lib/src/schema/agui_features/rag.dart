// Dart mirror of haiku.rag's `Citation` schema type, carrying the fields the
// frontend reads; `agui_feature_schema_drift_test.dart` lists the rest. The
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
