import 'package:meta/meta.dart';

/// Builds a LanceDB WHERE clause for the documents table from [documents].
///
/// Filters by document ID for exact matching. Duplicates are collapsed.
///
/// Single document: `id = 'abc-123'`
/// Multiple documents: `id IN ('abc-123', 'def-456')`
String buildDocumentFilter(List<RagDocument> documents) {
  if (documents.isEmpty) {
    throw ArgumentError.value(
      documents,
      'documents',
      'must not be empty',
    );
  }
  final ids = documents.map((d) => d.id).toSet();
  final escaped = ids.map((id) => id.replaceAll("'", "''")).toList();
  if (escaped.length == 1) {
    return "id = '${escaped.first}'";
  }
  return "id IN (${escaped.map((id) => "'$id'").join(', ')})";
}

/// Represents a document available for narrowing RAG searches.
///
/// Documents are fetched from a room and can be selected to limit
/// the scope of RAG queries to specific documents.
@immutable
class RagDocument {
  /// Creates a RAG document.
  const RagDocument({
    required this.id,
    required this.title,
    this.uri = '',
    this.metadata = const {},
    this.createdAt,
    this.updatedAt,
  });

  /// Unique identifier for the document (UUID).
  final String id;

  /// Display title of the document.
  final String title;

  /// Document URI (e.g. file path or URL).
  final String uri;

  /// Arbitrary metadata from the backend.
  final Map<String, dynamic> metadata;

  /// When the document was created.
  final DateTime? createdAt;

  /// When the document was last updated.
  final DateTime? updatedAt;

  /// Creates a copy of this document with the given fields replaced.
  RagDocument copyWith({
    String? id,
    String? title,
    String? uri,
    Map<String, dynamic>? metadata,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RagDocument(
      id: id ?? this.id,
      title: title ?? this.title,
      uri: uri ?? this.uri,
      metadata: metadata ?? this.metadata,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RagDocument && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'RagDocument(id: $id, title: $title, uri: $uri)';
}
