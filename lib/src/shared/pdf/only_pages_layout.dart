import 'package:flutter/foundation.dart' show immutable, setEquals;
import 'package:flutter/widgets.dart' show EdgeInsets, Offset, Rect, Size;
import 'package:pdfrx/pdfrx.dart';

/// Lays out only [pages] of a document, end to end as pdfrx's default
/// layout would lay out those pages alone, and hides the rest.
///
/// A hidden page keeps its place in the document, with no height, at the top
/// of the next page shown (or the bottom of the last): pdfrx paints and hits
/// nothing there, and a jump to it lands beside its neighbours. Pages keep
/// their numbers, so whatever is placed on a page by number still lands on
/// it.
@immutable
class OnlyPagesLayout extends PdfPageLayoutStrategy {
  const OnlyPagesLayout(this.pages);

  /// The 1-based numbers of the pages to show.
  final Set<int> pages;

  static const _sequential = SequentialPagesLayout();

  @override
  PdfPageLayout resolve(PdfPageLayoutContext context) {
    final all = context.pages;
    final shown = [
      for (var i = 0; i < all.length; i++)
        if (pages.contains(i + 1)) i,
    ];
    if (shown.isEmpty) return _sequential.resolve(context);

    final inner = _sequential.resolve(
      PdfPageLayoutContext(
        pages: [for (final i in shown) all[i]],
        viewport: context.viewport,
        boundaryMargin: context.boundaryMargin,
        paged: context.paged,
      ),
    );

    final rects = List<Rect?>.filled(all.length, null);
    for (var k = 0; k < shown.length; k++) {
      rects[shown[k]] = inner.pageLayouts[k];
    }
    // Each hidden page sits, flat, where the next shown page starts; past
    // the last shown page, where that one ends.
    Rect? next;
    for (var i = all.length - 1; i >= 0; i--) {
      final rect = rects[i];
      if (rect != null) {
        next = rect;
        continue;
      }
      final anchor = next;
      rects[i] = anchor != null
          ? Rect.fromLTWH(anchor.left, anchor.top, anchor.width, 0)
          : _after(inner.pageLayouts.last);
    }

    return PdfPageLayout(
      pageLayouts: [for (final rect in rects) rect!],
      documentSize: inner.documentSize,
      margin: inner.margin,
      fitMode: inner.fitMode,
      primaryAxis: inner.primaryAxis,
    );
  }

  static Rect _after(Rect last) =>
      Rect.fromLTWH(last.left, last.bottom, last.width, 0);

  @override
  bool operator ==(Object other) =>
      other is OnlyPagesLayout && setEquals(other.pages, pages);

  @override
  int get hashCode => Object.hashAllUnordered(pages);
}

/// Where the view should land once the pages shown change: a [page], and
/// the point of it to put at the view's top left, as a fraction of its
/// width and height.
typedef PdfPlace = ({int page, Offset fraction});

/// Where to land after the next change of pages shown; set just before
/// it, taken by the delegate as it lands there.
class PdfPlaceAfterRelayout {
  PdfPlace? pending;
}

/// pdfrx's default sizing, except where the pages shown change: there the
/// default keeps its place by the page in view as a fraction of its height,
/// which a hidden page — of no height — can't give, and the view lands at
/// the top. Instead the view goes to [place]'s pending place, at the zoom
/// it was at.
@immutable
class KeepPlaceSizeDelegateProvider extends PdfViewerSizeDelegateProvider {
  const KeepPlaceSizeDelegateProvider(this.place);

  final PdfPlaceAfterRelayout place;

  static const _default = PdfViewerSizeDelegateProviderLegacy();

  @override
  PdfViewerSizeDelegate create() =>
      _KeepPlaceSizeDelegate(_default.create(), place);

  @override
  bool operator ==(Object other) =>
      other is KeepPlaceSizeDelegateProvider && identical(other.place, place);

  @override
  int get hashCode => identityHashCode(place);
}

class _KeepPlaceSizeDelegate implements PdfViewerSizeDelegate {
  _KeepPlaceSizeDelegate(this._inner, this._place);

  final PdfViewerSizeDelegate _inner;
  final PdfPlaceAfterRelayout _place;
  PdfViewerController? _controller;

  @override
  void init(PdfViewerController controller) {
    _controller = controller;
    _inner.init(controller);
  }

  @override
  void dispose() {
    _controller = null;
    _inner.dispose();
  }

  @override
  PdfViewerLayoutMetrics calculateMetrics({
    required Size viewSize,
    required PdfPageLayout? layout,
    required int? pageNumber,
    required double pageMargin,
    required EdgeInsets? boundaryMargin,
  }) =>
      _inner.calculateMetrics(
        viewSize: viewSize,
        layout: layout,
        pageNumber: _shownPage(layout, pageNumber),
        pageMargin: pageMargin,
        boundaryMargin: boundaryMargin,
      );

  /// The zoom limits are measured on [pageNumber], the page that was in
  /// view; one just hidden has no height to measure, so the page the view
  /// is about to land on — or the nearest shown — stands in for it.
  int? _shownPage(PdfPageLayout? layout, int? pageNumber) {
    if (layout == null || pageNumber == null) return pageNumber;
    final rects = layout.pageLayouts;
    bool shown(int page) =>
        page >= 1 && page <= rects.length && rects[page - 1].height > 0;
    if (shown(pageNumber)) return pageNumber;
    final landing = _place.pending?.page;
    if (landing != null && shown(landing)) return landing;
    for (var distance = 1; distance < rects.length; distance++) {
      if (shown(pageNumber - distance)) return pageNumber - distance;
      if (shown(pageNumber + distance)) return pageNumber + distance;
    }
    return pageNumber;
  }

  @override
  double get onePassRenderingScaleThreshold =>
      _inner.onePassRenderingScaleThreshold;

  @override
  void onLayoutInitialized({
    required PdfViewerLayoutSnapshot state,
    required int initialPageNumber,
    required double coverScale,
    required double? alternativeFitScale,
    required PdfPageLayout layout,
    required PdfDocument document,
  }) =>
      _inner.onLayoutInitialized(
        state: state,
        initialPageNumber: initialPageNumber,
        coverScale: coverScale,
        alternativeFitScale: alternativeFitScale,
        layout: layout,
        document: document,
      );

  @override
  void onLayoutUpdate({
    required PdfViewerLayoutSnapshot oldState,
    required PdfViewerLayoutSnapshot newState,
    required double currentZoom,
    required Rect oldVisibleRect,
    required int? anchorPageNumber,
    required bool isLayoutChanged,
    required bool isViewSizeChanged,
  }) {
    final place = _place.pending;
    final layout = newState.layout;
    final controller = _controller;
    if (place == null ||
        !isLayoutChanged ||
        isViewSizeChanged ||
        layout == null ||
        controller == null ||
        place.page < 1 ||
        place.page > layout.pageLayouts.length) {
      _inner.onLayoutUpdate(
        oldState: oldState,
        newState: newState,
        currentZoom: currentZoom,
        oldVisibleRect: oldVisibleRect,
        anchorPageNumber: anchorPageNumber,
        isLayoutChanged: isLayoutChanged,
        isViewSizeChanged: isViewSizeChanged,
      );
      return;
    }
    _place.pending = null;
    final rect = layout.pageLayouts[place.page - 1];
    final zoom =
        currentZoom < newState.minScale ? newState.minScale : currentZoom;
    controller.goToPosition(
      documentOffset: Offset(
        rect.left + place.fraction.dx * rect.width,
        rect.top + place.fraction.dy * rect.height,
      ),
      zoom: zoom,
    );
  }
}

/// Where to land once [shownAfter] are the pages shown (null: every page),
/// with [page] in view and [fraction] of it at the view's top left: the same
/// point if that page still shows, else the top of the nearest page that
/// does — the earlier one on a tie.
PdfPlace placeAfter({
  required int page,
  required Offset fraction,
  required Set<int>? shownAfter,
}) {
  if (shownAfter == null || shownAfter.isEmpty || shownAfter.contains(page)) {
    return (page: page, fraction: fraction);
  }
  var nearest = shownAfter.first;
  for (final candidate in shownAfter) {
    final distance = (candidate - page).abs();
    final best = (nearest - page).abs();
    if (distance < best || (distance == best && candidate < nearest)) {
      nearest = candidate;
    }
  }
  return (page: nearest, fraction: Offset(fraction.dx, 0));
}
