import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// What the open document is showing, for the pane around it to read.
@immutable
class PdfViewStatus {
  const PdfViewStatus({
    this.pageNumber,
    this.pageCount,
    this.hasSelection = false,
    this.searching = false,
    this.matchCount = 0,
    this.currentMatch,
  });

  /// The page in view, 1-based; null until the document has laid out.
  final int? pageNumber;
  final int? pageCount;

  /// Whether text is selected, which is when *Ask about this* is offered.
  final bool hasSelection;

  /// Whether a search is still scanning pages.
  final bool searching;
  final int matchCount;

  /// The current match, 0-based; null with no matches.
  final int? currentMatch;

  PdfViewStatus copyWith({
    int? pageNumber,
    int? pageCount,
    bool? hasSelection,
    bool? searching,
    int? matchCount,
    int? Function()? currentMatch,
  }) =>
      PdfViewStatus(
        pageNumber: pageNumber ?? this.pageNumber,
        pageCount: pageCount ?? this.pageCount,
        hasSelection: hasSelection ?? this.hasSelection,
        searching: searching ?? this.searching,
        matchCount: matchCount ?? this.matchCount,
        currentMatch: currentMatch == null ? this.currentMatch : currentMatch(),
      );

  @override
  bool operator ==(Object other) =>
      other is PdfViewStatus &&
      other.pageNumber == pageNumber &&
      other.pageCount == pageCount &&
      other.hasSelection == hasSelection &&
      other.searching == searching &&
      other.matchCount == matchCount &&
      other.currentMatch == currentMatch;

  @override
  int get hashCode => Object.hash(
        pageNumber,
        pageCount,
        hasSelection,
        searching,
        matchCount,
        currentMatch,
      );
}

/// What taking the selection for a quote gave.
sealed class PdfSelectionResult {
  const PdfSelectionResult();
}

/// The selected text, whitespace collapsed, and the page it starts on.
final class PdfSelectedText extends PdfSelectionResult {
  const PdfSelectedText({required this.text, required this.pageNumber});

  final String text;
  final int pageNumber;
}

/// The document forbids copying its text, so it cannot be quoted.
final class PdfSelectionCopyForbidden extends PdfSelectionResult {
  const PdfSelectionCopyForbidden();
}

/// Drives an open document. The pane holds one per document it shows; the
/// real one wraps pdfrx, and tests supply a fake so no widget test loads
/// PDFium.
abstract interface class PdfDocumentController {
  ReadonlySignal<PdfViewStatus> get status;

  Future<void> goToPage(int pageNumber);
  Future<void> zoomIn();
  Future<void> zoomOut();

  /// Starts a search for [query], replacing any previous one. An empty query
  /// clears it.
  void search(String query);
  Future<void> nextMatch();
  Future<void> previousMatch();

  /// Takes the selected text for a quote and clears the selection; null when
  /// nothing is selected.
  Future<PdfSelectionResult?> takeSelection();
}

/// Everything a document view needs to open one document.
@immutable
class PdfDocumentViewRequest {
  const PdfDocumentViewRequest({
    required this.sourceName,
    required this.onReady,
    required this.onLoadFailed,
    required this.passwordProvider,
    this.bytes,
    this.uri,
    this.initialPage = 1,
    this.onAskAbout,
  }) : assert(
          (bytes == null) != (uri == null),
          'a document opens from bytes or from a URI',
        );

  /// The document's bytes, already fetched; or null when [uri] is given.
  final Uint8List? bytes;

  /// A public URL to load without credentials; or null when [bytes] is given.
  final Uri? uri;

  /// Names the document to pdfrx's caches; identifiers only.
  final String sourceName;
  final int initialPage;

  /// Called once the document is open, with the controller that drives it.
  final void Function(PdfDocumentController controller) onReady;

  /// Called when the document cannot be opened: a load that failed, a
  /// password that was never given, a file that is not a PDF.
  final void Function(Object error, StackTrace? stackTrace) onLoadFailed;

  /// Asked for a password, again after each wrong one; null gives up.
  final FutureOr<String?> Function() passwordProvider;

  /// Called from the document's context menu with text selected. Null hides
  /// the *Ask about this* entry.
  final VoidCallback? onAskAbout;
}

/// Builds the widget that shows one document. Injected so tests can stand
/// in for pdfrx.
typedef PdfDocumentViewFactory = Widget Function(
  PdfDocumentViewRequest request,
);
