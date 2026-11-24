import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../markdown/launch_markdown_link.dart';
import 'paper_highlight_painter.dart';
import 'pdf_document_view.dart';
import 'pdf_runtime.dart' if (dart.library.js_interop) 'pdf_runtime_web.dart';

/// The [PdfDocumentViewFactory] the app uses: pdfrx over PDFium.
///
/// Kept to translation between pdfrx and [PdfDocumentController]; anything
/// with a decision in it lives in the pane, where tests reach it through a
/// fake.
Widget pdfrxDocumentView(PdfDocumentViewRequest request) =>
    PdfrxDocumentView(request: request);

class PdfrxDocumentView extends StatefulWidget {
  const PdfrxDocumentView({super.key, required this.request});

  final PdfDocumentViewRequest request;

  @override
  State<PdfrxDocumentView> createState() => _PdfrxDocumentViewState();
}

class _PdfrxDocumentViewState extends State<PdfrxDocumentView>
    implements PdfDocumentController {
  final _viewer = PdfViewerController();
  late final PdfTextSearcher _searcher;
  late final VoidCallback _stopListening;
  final _status = signal(const PdfViewStatus());
  var _reportedReady = false;
  var _reportedFailure = false;

  @override
  ReadonlySignal<PdfViewStatus> get status => _status;

  @override
  void initState() {
    super.initState();
    ensurePdfRuntime();
    _searcher = PdfTextSearcher(_viewer);
    _stopListening = _searcher.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _stopListening();
    _searcher.dispose();
    _status.dispose();
    super.dispose();
  }

  /// pdfrx reports page changes and selections from inside layout, where a
  /// signal write would mark the pane's watchers dirty mid-frame; those wait
  /// for the frame to finish.
  void _update(PdfViewStatus Function(PdfViewStatus) change) {
    void apply() {
      if (mounted) _status.value = change(_status.value);
    }

    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) => apply());
    } else {
      apply();
    }
  }

  void _onSearchChanged() => _update(
        (s) => s.copyWith(
          searching: _searcher.isSearching,
          matchCount: _searcher.matches.length,
          currentMatch: () =>
              _searcher.matches.isEmpty ? null : _searcher.currentIndex,
        ),
      );

  @override
  Future<void> goToPage(int pageNumber) =>
      _viewer.goToPage(pageNumber: pageNumber);

  @override
  Future<void> zoomIn() => _viewer.zoomUp();

  @override
  Future<void> zoomOut() => _viewer.zoomDown();

  @override
  void search(String query) {
    final pattern = query.trim();
    if (pattern.isEmpty) {
      _searcher.resetTextSearch();
    } else {
      _searcher.startTextSearch(pattern);
    }
  }

  @override
  Future<void> nextMatch() => _searcher.goToNextMatch();

  @override
  Future<void> previousMatch() => _searcher.goToPrevMatch();

  @override
  Future<PdfSelectionResult?> takeSelection() async {
    final selection = _viewer.textSelectionDelegate;
    if (!selection.hasSelectedText) return null;
    if (!selection.isCopyAllowed) return const PdfSelectionCopyForbidden();
    final ranges = await selection.getSelectedTextRanges();
    if (ranges.isEmpty) return null;
    final text = ranges
        .map((range) => range.text)
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    await selection.clearTextSelection();
    _update((s) => s.copyWith(hasSelection: false));
    if (text.isEmpty) return null;
    return PdfSelectedText(text: text, pageNumber: ranges.first.pageNumber);
  }

  void _paintMatches(Canvas canvas, Rect pageRect, PdfPage page) {
    final range = _searcher.getMatchesRangeForPage(page.pageNumber);
    if (range == null) return;
    final others = <Rect>[];
    final active = <Rect>[];
    for (var i = range.start; i < range.end; i++) {
      final rects = _searcher.matches[i].enumerateFragmentBoundingRects().map(
            (fragment) => fragment.bounds
                .toRectInDocument(page: page, pageRect: pageRect),
          );
      (i == _searcher.currentIndex ? active : others).addAll(rects);
    }
    paintPaperMatches(canvas, others: others, active: active);
  }

  void _onViewerReady(PdfDocument document, PdfViewerController viewer) {
    _update(
      (s) => s.copyWith(
        pageCount: document.pages.length,
        pageNumber: viewer.pageNumber,
      ),
    );
    if (_reportedReady) return;
    _reportedReady = true;
    widget.request.onReady(this);
  }

  /// pdfrx builds its error banner from inside the viewer's build; the
  /// failure reaches the pane after the frame, once.
  Widget _onLoadError(Object error, StackTrace? stackTrace) {
    if (!_reportedFailure) {
      _reportedFailure = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.request.onLoadFailed(error, stackTrace);
      });
    }
    return const SizedBox.shrink();
  }

  void _onLinkTap(PdfLink link) {
    final url = link.url;
    if (url != null) {
      unawaited(launchMarkdownLink(url.toString()));
    } else if (link.dest != null) {
      unawaited(_viewer.goToDest(link.dest));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final request = widget.request;
    final onAskAbout = request.onAskAbout;
    final params = PdfViewerParams(
      backgroundColor: theme.colorScheme.surfaceContainerLow,
      onViewerReady: _onViewerReady,
      onPageChanged: (page) => _update((s) => s.copyWith(pageNumber: page)),
      pagePaintCallbacks: [_paintMatches],
      textSelectionParams: PdfTextSelectionParams(
        onTextSelectionChange: (selection) => _update(
          (s) => s.copyWith(hasSelection: selection.hasSelectedText),
        ),
      ),
      customizeContextMenuItems: onAskAbout == null
          ? null
          : (params, items) {
              if (!params.textSelectionDelegate.hasSelectedText) return;
              items.insert(
                0,
                ContextMenuButtonItem(
                  label: 'Ask about this',
                  onPressed: () {
                    params.dismissContextMenu();
                    onAskAbout();
                  },
                ),
              );
            },
      errorBannerBuilder: (context, error, stackTrace, _) =>
          _onLoadError(error, stackTrace),
      linkHandlerParams: PdfLinkHandlerParams(onLinkTap: _onLinkTap),
    );

    final bytes = request.bytes;
    final viewer = bytes != null
        ? PdfViewer.data(
            bytes,
            sourceName: request.sourceName,
            passwordProvider: request.passwordProvider,
            controller: _viewer,
            initialPageNumber: request.initialPage,
            params: params,
          )
        : PdfViewer.uri(
            request.uri!,
            passwordProvider: request.passwordProvider,
            controller: _viewer,
            initialPageNumber: request.initialPage,
            params: params,
          );

    // Selection is painted on paper, not on the app's surfaces, so it takes
    // the paper token rather than the theme's selection colour.
    return Theme(
      data: theme.copyWith(
        textSelectionTheme: theme.textSelectionTheme.copyWith(
          selectionColor: PaperHighlights.selection,
        ),
      ),
      child: viewer,
    );
  }
}
