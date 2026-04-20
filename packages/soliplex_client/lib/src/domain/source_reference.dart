import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A stable, frontend-owned citation reference.
///
/// Unlike schema types (which are generated from backend and may change),
/// SourceReference is controlled by the frontend and provides a stable API
/// for UI components to display citation information.
@immutable
class SourceReference {
  /// Creates a source reference.
  const SourceReference({
    required this.documentId,
    required this.documentUri,
    required this.content,
    required this.chunkId,
    this.documentTitle,
    this.headings = const [],
    this.pageNumbers = const [],
    this.index,
  });

  /// Unique identifier for the document.
  final String documentId;

  /// URI to access the document.
  final String documentUri;

  /// The cited text content.
  final String content;

  /// Unique identifier for this chunk within the document.
  final String chunkId;

  /// Human-readable document title, if available.
  final String? documentTitle;

  /// Heading hierarchy leading to this content.
  final List<String> headings;

  /// Page numbers where this content appears.
  final List<int> pageNumbers;

  /// Display index for numbered citations.
  final int? index;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! SourceReference) return false;
    const listEquals = ListEquality<dynamic>();
    return documentId == other.documentId &&
        documentUri == other.documentUri &&
        content == other.content &&
        chunkId == other.chunkId &&
        documentTitle == other.documentTitle &&
        listEquals.equals(headings, other.headings) &&
        listEquals.equals(pageNumbers, other.pageNumbers) &&
        index == other.index;
  }

  @override
  int get hashCode => Object.hash(
    documentId,
    documentUri,
    content,
    chunkId,
    documentTitle,
    const ListEquality<String>().hash(headings),
    const ListEquality<int>().hash(pageNumbers),
    index,
  );

  @override
  String toString() =>
      'SourceReference('
      'documentId: $documentId, '
      'chunkId: $chunkId, '
      'index: $index)';
}

/// Formatting utilities for [SourceReference] display.
extension SourceReferenceFormatting on SourceReference {
  /// Formats page numbers for display.
  ///
  /// Returns:
  /// - `null` if no page numbers
  /// - `"p.5"` for single page
  /// - `"p.1-3"` for consecutive pages
  /// - `"p.1, 5, 10"` for non-consecutive pages
  String? get formattedPageNumbers {
    if (pageNumbers.isEmpty) return null;
    if (pageNumbers.length == 1) return 'p.${pageNumbers.first}';

    final sorted = [...pageNumbers]..sort();

    var isConsecutive = true;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] != sorted[i - 1] + 1) {
        isConsecutive = false;
        break;
      }
    }

    if (isConsecutive) {
      return 'p.${sorted.first}-${sorted.last}';
    } else {
      return 'p.${sorted.join(', ')}';
    }
  }

  /// Returns a display-friendly title for the source reference.
  ///
  /// Uses [documentTitle] if present, otherwise extracts filename from
  /// [documentUri]. Falls back to "Unknown Document" if neither works.
  String get displayTitle {
    if (documentTitle != null && documentTitle!.isNotEmpty) {
      return documentTitle!;
    }

    final uri = Uri.tryParse(documentUri);
    if (uri != null && uri.pathSegments.isNotEmpty) {
      return uri.pathSegments.last;
    }

    return 'Unknown Document';
  }

  /// Whether this source reference points to a PDF document.
  bool get isPdf => documentUri.toLowerCase().endsWith('.pdf');
}
