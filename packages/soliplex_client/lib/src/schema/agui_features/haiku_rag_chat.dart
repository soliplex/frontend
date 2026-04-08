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
//     final haikuRagChat = haikuRagChatFromJson(jsonString);

import 'dart:convert';

HaikuRagChat haikuRagChatFromJson(String str) =>
    HaikuRagChat.fromJson(json.decode(str));

String haikuRagChatToJson(HaikuRagChat data) => json.encode(data.toJson());

///State shared between frontend and agent via AG-UI.
class HaikuRagChat {
  final Map<String, int>? citationRegistry;
  final List<Citation>? citations;
  final List<List<Citation>>? citationsHistory;
  final String? documentFilter;
  final String? initialContext;
  final List<QaResponse>? qaHistory;
  final SessionContext? sessionContext;
  final String? sessionId;

  HaikuRagChat({
    this.citationRegistry,
    this.citations,
    this.citationsHistory,
    this.documentFilter,
    this.initialContext,
    this.qaHistory,
    this.sessionContext,
    this.sessionId,
  });

  factory HaikuRagChat.fromJson(Map<String, dynamic> json) => HaikuRagChat(
        citationRegistry: Map.from(
          json["citation_registry"]!,
        ).map((k, v) => MapEntry<String, int>(k, v)),
        citations: json["citations"] == null
            ? []
            : List<Citation>.from(
                json["citations"]!.map((x) => Citation.fromJson(x)),
              ),
        citationsHistory: json["citations_history"] == null
            ? []
            : List<List<Citation>>.from(
                json["citations_history"]!.map(
                  (x) =>
                      List<Citation>.from(x.map((y) => Citation.fromJson(y))),
                ),
              ),
        documentFilter: json["document_filter"],
        initialContext: json["initial_context"],
        qaHistory: json["qa_history"] == null
            ? []
            : List<QaResponse>.from(
                json["qa_history"]!.map((x) => QaResponse.fromJson(x)),
              ),
        sessionContext: json["session_context"] == null
            ? null
            : SessionContext.fromJson(json["session_context"]),
        sessionId: json["session_id"],
      );

  Map<String, dynamic> toJson() => {
        "citation_registry": Map.from(
          citationRegistry!,
        ).map((k, v) => MapEntry<String, dynamic>(k, v)),
        "citations": citations == null
            ? []
            : List<dynamic>.from(citations!.map((x) => x.toJson())),
        "citations_history": citationsHistory == null
            ? []
            : List<dynamic>.from(
                citationsHistory!.map(
                  (x) => List<dynamic>.from(x.map((y) => y.toJson())),
                ),
              ),
        "document_filter": documentFilter,
        "initial_context": initialContext,
        "qa_history": qaHistory == null
            ? []
            : List<dynamic>.from(qaHistory!.map((x) => x.toJson())),
        "session_context": sessionContext?.toJson(),
        "session_id": sessionId,
      };
}

///Resolved citation with full metadata for display/visual grounding.
///
///Used by both research graph and chat agent. The optional index field
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

///A Q&A pair from conversation history with citations.
class QaResponse {
  final String answer;
  final List<Citation>? citations;
  final double? confidence;
  final String question;
  final List<double>? questionEmbedding;

  QaResponse({
    required this.answer,
    this.citations,
    this.confidence,
    required this.question,
    this.questionEmbedding,
  });

  factory QaResponse.fromJson(Map<String, dynamic> json) => QaResponse(
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

///Compressed summary of conversation history for research graph.
class SessionContext {
  final DateTime? lastUpdated;
  final String? summary;

  SessionContext({this.lastUpdated, this.summary});

  factory SessionContext.fromJson(Map<String, dynamic> json) => SessionContext(
        lastUpdated: json["last_updated"] == null
            ? null
            : DateTime.parse(json["last_updated"]),
        summary: json["summary"],
      );

  Map<String, dynamic> toJson() => {
        "last_updated": lastUpdated?.toIso8601String(),
        "summary": summary,
      };
}
