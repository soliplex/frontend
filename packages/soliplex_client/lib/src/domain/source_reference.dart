import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

/// A stable, frontend-owned citation reference.
///
/// Unlike schema types (which mirror the backend wire format and may change),
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
    this.docItemRefs = const [],
    this.pictureRefs = const [],
    this.chunkIds = const [],
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

  /// The doc-item refs the model saw for this citation, passed to the
  /// visualization endpoint so the highlight matches the cited content.
  final List<String> docItemRefs;

  /// Self-refs of the picture items in the cited content, used to fetch and
  /// render the cited figures inline. Empty for text-only citations.
  final List<String> pictureRefs;

  /// Ids of all chunks whose expansion merged into this citation (always
  /// includes [chunkId]) — merge provenance sent by the backend.
  ///
  /// Parsed and carried through so no backend field is silently dropped, but
  /// intentionally not shown in the UI: visualization grounds off
  /// [docItemRefs], which already spans the merged content, so `chunk_ids` is
  /// redundant for rendering. Kept for a future consumer (e.g. multi-chunk
  /// visualization).
  final List<String> chunkIds;

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
        listEquals.equals(docItemRefs, other.docItemRefs) &&
        listEquals.equals(pictureRefs, other.pictureRefs) &&
        listEquals.equals(chunkIds, other.chunkIds) &&
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
        const ListEquality<String>().hash(docItemRefs),
        const ListEquality<String>().hash(pictureRefs),
        const ListEquality<String>().hash(chunkIds),
        index,
      );

  @override
  String toString() => 'SourceReference('
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
