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
  PdfPassage? _passage;
  List<PdfTextBlock>? _textBlocks;
  PdfTextBlock? _selectedBlock;
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

  @override
  Future<void> showPassage(PdfPassage? passage) async {
    _passage = passage;
    _viewer.invalidate();
    final page = passage?.firstPage;
    if (passage == null || page == null) return;
    final onPage = [
      ...passage.anchor.where((box) => box.page == page),
      if (!passage.anchor.any((box) => box.page == page))
        ...passage.context.where((box) => box.page == page),
    ].map(_pdfRect);
    await _viewer.goToRectInsidePage(
      pageNumber: page,
      rect: onPage.reduce((a, b) => a.merge(b)),
      anchor: PdfPageAnchor.center,
    );
  }

  /// A box as pdfrx's rect, its edges ordered whichever way they came.
  static PdfRect _pdfRect(PdfPassageBox box) => PdfRect(
        box.left < box.right ? box.left : box.right,
        box.top > box.bottom ? box.top : box.bottom,
        box.left < box.right ? box.right : box.left,
        box.top > box.bottom ? box.bottom : box.top,
      );

  void _paintPassage(Canvas canvas, Rect pageRect, PdfPage page) {
    final passage = _passage;
    if (passage == null) return;
    Iterable<Rect> onPage(List<PdfPassageBox> boxes) =>
        boxes.where((box) => box.page == page.pageNumber).map(
              (box) => _pdfRect(box)
                  .toRectInDocument(page: page, pageRect: pageRect),
            );
    paintPaperPassage(
      canvas,
      context: onPage(passage.context),
      anchor: onPage(passage.anchor),
    );
  }

  @override
  void showTextBlocks(List<PdfTextBlock>? blocks, {PdfTextBlock? selected}) {
    if (!mounted) return;
    setState(() {
      _textBlocks = blocks;
      _selectedBlock = blocks == null ? null : selected;
    });
    _viewer.invalidate();
  }

  /// The blocks to show on [page]: only where the page has no text of its
  /// own, since anywhere else the text can be selected as it is.
  Iterable<PdfTextBlock> _blocksOn(PdfPage page) {
    final blocks = _textBlocks;
    if (blocks == null ||
        !_status.value.textlessPages.contains(page.pageNumber)) {
      return const [];
    }
    return blocks.where((block) => block.box.page == page.pageNumber);
  }

  void _paintTextBlocks(Canvas canvas, Rect pageRect, PdfPage page) {
    Rect place(PdfTextBlock block) =>
        _pdfRect(block.box).toRectInDocument(page: page, pageRect: pageRect);
    final blocks = _blocksOn(page).toList();
    if (blocks.isEmpty) return;
    final selected = _selectedBlock;
    paintPaperTextBlocks(
      canvas,
      blocks: blocks.map(place),
      selected: selected != null && blocks.contains(selected)
          ? place(selected)
          : null,
    );
  }

  /// A tap target over each block, in the page's own coordinates; the
  /// viewer still pans and zooms over them.
  List<Widget> _textBlockTargets(
    BuildContext context,
    Rect pageRect,
    PdfPage page,
  ) {
    final onTap = widget.request.onTextBlockTap;
    if (onTap == null) return const [];
    return [
      for (final block in _blocksOn(page))
        Positioned.fromRect(
          rect: _pdfRect(block.box)
              .toRect(page: page, scaledPageSize: pageRect.size),
          child: Semantics(
            button: true,
            label: block.text,
            // The hand says the frame opens something, as a link would. It
            // wraps the region, as pdfrx's own link overlay does: the region
            // puts its child behind an IgnorePointer, where no hover reaches.
            // Translucent and not opaque, so pans and selection still pass.
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              hitTestBehavior: HitTestBehavior.translucent,
              opaque: false,
              child: PdfOverlayInteractionRegion(
                onTap: (_) {
                  onTap(block);
                  return true;
                },
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
    ];
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
    unawaited(_findTextlessPages(document));
  }

  /// Fewer characters than this on a page, whitespace aside, and the page
  /// counts as carrying no text: a scan, perhaps with a stray OCR'd page
  /// number or a watermark.
  static const _textlessBelow = 16;

  /// Checks each page for text of its own, one at a time after the
  /// document opens, reporting the textless ones as they are found.
  Future<void> _findTextlessPages(PdfDocument document) async {
    final found = <int>{};
    for (final page in document.pages) {
      final PdfPageRawText? text;
      try {
        text = await page.loadText();
      } on Exception {
        // A page whose text can't be read is left as it is: it still has
        // whatever selection pdfrx can give it.
        continue;
      }
      if (!mounted) return;
      if (text == null) continue;
      final characters = text.fullText.replaceAll(RegExp(r'\s'), '').length;
      if (characters < _textlessBelow) {
        found.add(page.pageNumber);
        _update((s) => s.copyWith(textlessPages: {...found}));
      }
    }
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
      // The passage first, so a search match shows on top of it.
      pagePaintCallbacks: [_paintPassage, _paintTextBlocks, _paintMatches],
      pageOverlaysBuilder: _textBlockTargets,
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
