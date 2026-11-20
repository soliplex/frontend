import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals, setEquals;
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
    this.textlessPages = const {},
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

  /// Pages found to carry no text of their own — scans, typically — so
  /// nothing on them can be selected or searched. Pages are checked after
  /// the document opens, so this grows as they are.
  final Set<int> textlessPages;

  PdfViewStatus copyWith({
    int? pageNumber,
    int? pageCount,
    bool? hasSelection,
    bool? searching,
    int? matchCount,
    int? Function()? currentMatch,
    Set<int>? textlessPages,
  }) =>
      PdfViewStatus(
        pageNumber: pageNumber ?? this.pageNumber,
        pageCount: pageCount ?? this.pageCount,
        hasSelection: hasSelection ?? this.hasSelection,
        searching: searching ?? this.searching,
        matchCount: matchCount ?? this.matchCount,
        currentMatch: currentMatch == null ? this.currentMatch : currentMatch(),
        textlessPages: textlessPages ?? this.textlessPages,
      );

  @override
  bool operator ==(Object other) =>
      other is PdfViewStatus &&
      other.pageNumber == pageNumber &&
      other.pageCount == pageCount &&
      other.hasSelection == hasSelection &&
      other.searching == searching &&
      other.matchCount == matchCount &&
      other.currentMatch == currentMatch &&
      setEquals(other.textlessPages, textlessPages);

  @override
  int get hashCode => Object.hash(
        pageNumber,
        pageCount,
        hasSelection,
        searching,
        matchCount,
        currentMatch,
        Object.hashAllUnordered(textlessPages),
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

/// One box on a page of the document, in PDF points with the origin at the
/// page's bottom left, as the PDF's own coordinates are.
@immutable
class PdfPassageBox {
  const PdfPassageBox({
    required this.page,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  /// The 1-based page the box is on.
  final int page;
  final double left;
  final double top;
  final double right;
  final double bottom;

  @override
  bool operator ==(Object other) =>
      other is PdfPassageBox &&
      other.page == page &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(page, left, top, right, bottom);
}

/// A passage to mark in the document: the [anchor] it is about, drawn as the
/// current match is, over a fainter wash on its [context].
@immutable
class PdfPassage {
  const PdfPassage({required this.anchor, this.context = const []});

  final List<PdfPassageBox> anchor;
  final List<PdfPassageBox> context;

  /// The page to show the passage on: its anchor's first, else its
  /// context's; null when it has no boxes at all.
  int? get firstPage => anchor.firstOrNull?.page ?? context.firstOrNull?.page;

  @override
  bool operator ==(Object other) =>
      other is PdfPassage &&
      listEquals(other.anchor, anchor) &&
      listEquals(other.context, context);

  @override
  int get hashCode =>
      Object.hash(Object.hashAll(anchor), Object.hashAll(context));
}

/// A block of text recovered for a page that has none of its own — by OCR,
/// when the document was ingested — and the [box] it was read from.
@immutable
class PdfTextBlock {
  const PdfTextBlock({required this.box, required this.text});

  final PdfPassageBox box;
  final String text;

  @override
  bool operator ==(Object other) =>
      other is PdfTextBlock && other.box == box && other.text == text;

  @override
  int get hashCode => Object.hash(box, text);
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

  /// Marks [passage] in the document, replacing any passage marked before,
  /// and brings its first page's anchor into view; null clears the marks.
  Future<void> showPassage(PdfPassage? passage);

  /// Shows [blocks] over the pages without text of their own, each one a
  /// target that reports a tap to [PdfDocumentViewRequest.onTextBlockTap];
  /// [selected], if given, is drawn as chosen. Null hides them.
  void showTextBlocks(List<PdfTextBlock>? blocks, {PdfTextBlock? selected});
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
    this.onTextBlockTap,
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

  /// Called when one of the blocks [PdfDocumentController.showTextBlocks]
  /// shows is tapped.
  final void Function(PdfTextBlock block)? onTextBlockTap;
}

/// Builds the widget that shows one document. Injected so tests can stand
/// in for pdfrx.
typedef PdfDocumentViewFactory = Widget Function(
  PdfDocumentViewRequest request,
);
