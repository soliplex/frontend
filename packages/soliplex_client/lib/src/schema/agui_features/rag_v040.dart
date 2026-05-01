// Hand-written types for the haiku.rag 0.40 `rag` namespace state shape.
//
// The 0.42 shape (see `rag.dart`) is the target schema and generated from
// quicktype. These types capture the 0.40 wire format so clients can still
// parse state emitted by backends pinned to haiku.rag 0.40 and replay
// 0.40-era thread history.
//
// Shared types (`Citation`, `SearchResult`) are imported from `rag.dart`
// because their Pydantic definitions are byte-identical between 0.40 and
// 0.42. This file adds only the 0.40-exclusive types:
//
// - `QaHistoryEntry` (`qa_history` list entries)
// - `DocumentInfo`   (`documents` list entries)
// - `ResearchEntry`  (`reports` list entries)

import 'package:soliplex_client/src/schema/agui_features/rag.dart';

class RagV040 {
  final List<Citation>? citations;
  final String? documentFilter;
  final List<DocumentInfo>? documents;
  final List<QaHistoryEntry>? qaHistory;
  final List<ResearchEntry>? reports;
  final Map<String, List<SearchResult>>? searches;

  RagV040({
    this.citations,
    this.documentFilter,
    this.documents,
    this.qaHistory,
    this.reports,
    this.searches,
  });

  factory RagV040.fromJson(Map<String, dynamic> json) => RagV040(
        citations: json['citations'] == null
            ? []
            : List<Citation>.from(
                (json['citations'] as List).map(
                  (x) => Citation.fromJson(x as Map<String, dynamic>),
                ),
              ),
        documentFilter: json['document_filter'] as String?,
        documents: json['documents'] == null
            ? []
            : List<DocumentInfo>.from(
                (json['documents'] as List).map(
                  (x) => DocumentInfo.fromJson(x as Map<String, dynamic>),
                ),
              ),
        qaHistory: json['qa_history'] == null
            ? []
            : List<QaHistoryEntry>.from(
                (json['qa_history'] as List).map(
                  (x) => QaHistoryEntry.fromJson(x as Map<String, dynamic>),
                ),
              ),
        reports: json['reports'] == null
            ? []
            : List<ResearchEntry>.from(
                (json['reports'] as List).map(
                  (x) => ResearchEntry.fromJson(x as Map<String, dynamic>),
                ),
              ),
        searches: json['searches'] == null
            ? null
            : Map.from(json['searches'] as Map).map(
                (k, v) => MapEntry<String, List<SearchResult>>(
                  k as String,
                  List<SearchResult>.from(
                    (v as List).map(
                      (x) => SearchResult.fromJson(x as Map<String, dynamic>),
                    ),
                  ),
                ),
              ),
      );

  Map<String, dynamic> toJson() => {
        'citations': citations == null
            ? []
            : List<dynamic>.from(citations!.map((x) => x.toJson())),
        'document_filter': documentFilter,
        'documents': documents == null
            ? []
            : List<dynamic>.from(documents!.map((x) => x.toJson())),
        'qa_history': qaHistory == null
            ? []
            : List<dynamic>.from(qaHistory!.map((x) => x.toJson())),
        'reports': reports == null
            ? []
            : List<dynamic>.from(reports!.map((x) => x.toJson())),
        'searches': searches == null
            ? null
            : Map.from(searches!).map(
                (k, v) => MapEntry<String, dynamic>(
                  k as String,
                  List<dynamic>.from(
                    (v as List<SearchResult>).map((x) => x.toJson()),
                  ),
                ),
              ),
      };
}

/// A Q&A pair with optional citations.
///
/// Mirrors `haiku.rag.tools.qa.QAHistoryEntry`. The backend's
/// `question_embedding` field is marked `exclude=True` and does not appear
/// in the wire format, so it is not modelled here.
class QaHistoryEntry {
  final String question;
  final String answer;
  final double confidence;
  final List<Citation>? citations;

  QaHistoryEntry({
    required this.question,
    required this.answer,
    this.confidence = 0.9,
    this.citations,
  });

  factory QaHistoryEntry.fromJson(Map<String, dynamic> json) => QaHistoryEntry(
        question: json['question'] as String,
        answer: json['answer'] as String,
        confidence: (json['confidence'] as num?)?.toDouble() ?? 0.9,
        citations: json['citations'] == null
            ? null
            : List<Citation>.from(
                (json['citations'] as List).map(
                  (x) => Citation.fromJson(x as Map<String, dynamic>),
                ),
              ),
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'answer': answer,
        'confidence': confidence,
        'citations': citations == null
            ? null
            : List<dynamic>.from(citations!.map((x) => x.toJson())),
      };
}

/// Document info for `list_documents` responses.
///
/// Mirrors `haiku.rag.tools.document.DocumentInfo`. `id` is optional per the
/// backend model.
class DocumentInfo {
  final String? id;
  final String title;
  final String uri;
  final String created;

  DocumentInfo({
    this.id,
    required this.title,
    required this.uri,
    required this.created,
  });

  factory DocumentInfo.fromJson(Map<String, dynamic> json) => DocumentInfo(
        id: json['id'] as String?,
        title: json['title'] as String,
        uri: json['uri'] as String,
        created: json['created'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'uri': uri,
        'created': created,
      };
}

/// A research report emitted by the 0.40 research graph.
///
/// Mirrors `haiku.rag.skills._tools.ResearchEntry`.
class ResearchEntry {
  final String question;
  final String title;
  final String executiveSummary;

  ResearchEntry({
    required this.question,
    required this.title,
    required this.executiveSummary,
  });

  factory ResearchEntry.fromJson(Map<String, dynamic> json) => ResearchEntry(
        question: json['question'] as String,
        title: json['title'] as String,
        executiveSummary: json['executive_summary'] as String,
      );

  Map<String, dynamic> toJson() => {
        'question': question,
        'title': title,
        'executive_summary': executiveSummary,
      };
}
