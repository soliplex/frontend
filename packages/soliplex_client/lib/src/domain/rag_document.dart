import 'package:meta/meta.dart';
import 'package:soliplex_client/src/utils/source_url.dart';

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

/// Parses the id list out of a WHERE clause produced by [buildDocumentFilter].
///
/// Extracts every SQL single-quoted literal in order, unescaping doubled
/// quotes (`''` -> `'`), which recovers the ids from both shapes the builder
/// emits (`id = '<id>'` and `id IN ('<id>', ...)`). Any other or empty input
/// yields `const []`; this never throws, so a malformed stored filter degrades
/// to "no selection" rather than crashing hydration.
List<String> parseDocumentFilter(String filter) {
  final ids = <String>[];
  var i = 0;
  while (i < filter.length) {
    if (filter[i] != "'") {
      i++;
      continue;
    }
    i++; // consume the opening quote
    final buffer = StringBuffer();
    var foundClosingQuote = false;
    while (i < filter.length) {
      if (filter[i] == "'") {
        if (i + 1 < filter.length && filter[i + 1] == "'") {
          buffer.write("'"); // escaped quote
          i += 2;
          continue;
        }
        i++; // consume the closing quote
        foundClosingQuote = true;
        break;
      }
      buffer.write(filter[i]);
      i++;
    }
    if (foundClosingQuote) {
      ids.add(buffer.toString());
    }
  }
  return ids;
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

  /// The document's clickable origin URL, from the `source_url` metadata key.
  ///
  /// Null when absent, empty, non-string, or not a web URL — see
  /// [sourceUrlFromMetadata].
  Uri? get sourceUrl => sourceUrlFromMetadata(metadata);

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
