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
  final List<Citation>? citations;
  final String? documentFilter;
  final List<DocumentInfo>? documents;
  final List<QaHistoryEntry>? qaHistory;
  final List<ResearchEntry>? reports;
  final Map<String, List<SearchResult>>? searches;

  Rag({
    this.citations,
    this.documentFilter,
    this.documents,
    this.qaHistory,
    this.reports,
    this.searches,
  });

  factory Rag.fromJson(Map<String, dynamic> json) => Rag(
        citations: json["citations"] == null
            ? []
            : List<Citation>.from(
                json["citations"]!.map((x) => Citation.fromJson(x)),
              ),
        documentFilter: json["document_filter"],
        documents: json["documents"] == null
            ? []
            : List<DocumentInfo>.from(
                json["documents"]!.map((x) => DocumentInfo.fromJson(x)),
              ),
        qaHistory: json["qa_history"] == null
            ? []
            : List<QaHistoryEntry>.from(
                json["qa_history"]!.map((x) => QaHistoryEntry.fromJson(x)),
              ),
        reports: json["reports"] == null
            ? []
            : List<ResearchEntry>.from(
                json["reports"]!.map((x) => ResearchEntry.fromJson(x)),
              ),
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
        "citations": citations == null
            ? []
            : List<dynamic>.from(citations!.map((x) => x.toJson())),
        "document_filter": documentFilter,
        "documents": documents == null
            ? []
            : List<dynamic>.from(documents!.map((x) => x.toJson())),
        "qa_history": qaHistory == null
            ? []
            : List<dynamic>.from(qaHistory!.map((x) => x.toJson())),
        "reports": reports == null
            ? []
            : List<dynamic>.from(reports!.map((x) => x.toJson())),
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
  final String content;
  final String documentId;
  final String? documentTitle;
  final String documentUri;
  final List<String>? headings;
  final int? index;
  final List<int>? pageNumbers;

  Citation({
    required this.chunkId,
    required this.content,
    required this.documentId,
    this.documentTitle,
    required this.documentUri,
    this.headings,
    this.index,
    this.pageNumbers,
  });

  factory Citation.fromJson(Map<String, dynamic> json) => Citation(
        chunkId: json["chunk_id"],
        content: json["content"],
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
      );

  Map<String, dynamic> toJson() => {
        "chunk_id": chunkId,
        "content": content,
        "document_id": documentId,
        "document_title": documentTitle,
        "document_uri": documentUri,
        "headings":
            headings == null ? [] : List<dynamic>.from(headings!.map((x) => x)),
        "index": index,
        "page_numbers": pageNumbers == null
            ? []
            : List<dynamic>.from(pageNumbers!.map((x) => x)),
      };
}

///Document info for list_documents response.
class DocumentInfo {
  final String created;
  final String? id;
  final String title;
  final String uri;

  DocumentInfo({
    required this.created,
    this.id,
    required this.title,
    required this.uri,
  });

  factory DocumentInfo.fromJson(Map<String, dynamic> json) => DocumentInfo(
        created: json["created"],
        id: json["id"],
        title: json["title"],
        uri: json["uri"],
      );

  Map<String, dynamic> toJson() => {
        "created": created,
        "id": id,
        "title": title,
        "uri": uri,
      };
}

///A Q&A pair with optional cached embedding for similarity matching.
class QaHistoryEntry {
  final String answer;
  final List<Citation>? citations;
  final double? confidence;
  final String question;
  final List<double>? questionEmbedding;

  QaHistoryEntry({
    required this.answer,
    this.citations,
    this.confidence,
    required this.question,
    this.questionEmbedding,
  });

  factory QaHistoryEntry.fromJson(Map<String, dynamic> json) => QaHistoryEntry(
        answer: json["answer"],
        citations: json["citations"] == null
            ? []
            : List<Citation>.from(
                json["citations"]!.map((x) => Citation.fromJson(x)),
              ),
        confidence: json["confidence"]?.toDouble(),
        question: json["question"],
        questionEmbedding: json["question_embedding"] == null
            ? []
            : List<double>.from(
                json["question_embedding"]!.map((x) => x?.toDouble()),
              ),
      );

  Map<String, dynamic> toJson() => {
        "answer": answer,
        "citations": citations == null
            ? []
            : List<dynamic>.from(citations!.map((x) => x.toJson())),
        "confidence": confidence,
        "question": question,
        "question_embedding": questionEmbedding == null
            ? []
            : List<dynamic>.from(questionEmbedding!.map((x) => x)),
      };
}

class ResearchEntry {
  final String executiveSummary;
  final String question;
  final String title;

  ResearchEntry({
    required this.executiveSummary,
    required this.question,
    required this.title,
  });

  factory ResearchEntry.fromJson(Map<String, dynamic> json) => ResearchEntry(
        executiveSummary: json["executive_summary"],
        question: json["question"],
        title: json["title"],
      );

  Map<String, dynamic> toJson() => {
        "executive_summary": executiveSummary,
        "question": question,
        "title": title,
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
        "page_numbers": pageNumbers == null
            ? []
            : List<dynamic>.from(pageNumbers!.map((x) => x)),
        "score": score,
      };
}
