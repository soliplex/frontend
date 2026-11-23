import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:soliplex_frontend/src/shared/pdf/only_pages_layout.dart';

/// A page with a size and nothing else: all a layout reads.
class _Page implements PdfPage {
  _Page(this.width, this.height);

  @override
  final double width;

  @override
  final double height;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final pages = [
    _Page(600, 800),
    _Page(600, 700),
    _Page(600, 900),
    _Page(600, 500),
    _Page(600, 600),
  ];
  const viewport = Size(800, 1000);

  PdfPageLayout resolve(PdfPageLayoutStrategy strategy, List<PdfPage> of) =>
      strategy.resolve(PdfPageLayoutContext(pages: of, viewport: viewport));

  test('lays out the pages shown as the default layout lays them out alone',
      () {
    final only = resolve(const OnlyPagesLayout({2, 4}), pages);
    final alone = resolve(const SequentialPagesLayout(), [pages[1], pages[3]]);

    expect(only.pageLayouts, hasLength(5));
    expect(only.pageLayouts[1], alone.pageLayouts[0]);
    expect(only.pageLayouts[3], alone.pageLayouts[1]);
    expect(only.documentSize, alone.documentSize);
    expect(only.margin, alone.margin);
  });

  test('flattens each hidden page where the next shown page starts', () {
    final only = resolve(const OnlyPagesLayout({2, 4}), pages);
    final second = only.pageLayouts[1];
    final fourth = only.pageLayouts[3];

    expect(only.pageLayouts[0].height, 0);
    expect(only.pageLayouts[0].top, second.top);
    expect(only.pageLayouts[2].height, 0);
    expect(only.pageLayouts[2].top, fourth.top);
  });

  test('flattens the hidden pages past the last shown one at its end', () {
    final only = resolve(const OnlyPagesLayout({2, 4}), pages);

    expect(only.pageLayouts[4].height, 0);
    expect(only.pageLayouts[4].top, only.pageLayouts[3].bottom);
  });

  test('shows every page when none of those named exists', () {
    final only = resolve(const OnlyPagesLayout({9}), pages);
    final all = resolve(const SequentialPagesLayout(), pages);

    expect(only.pageLayouts, all.pageLayouts);
  });

  test('compares by the pages it shows', () {
    expect(const OnlyPagesLayout({1, 3}), const OnlyPagesLayout({3, 1}));
    expect(
      const OnlyPagesLayout({1, 3}).hashCode,
      const OnlyPagesLayout({3, 1}).hashCode,
    );
    expect(const OnlyPagesLayout({1, 3}), isNot(const OnlyPagesLayout({1})));
  });

  group('placeAfter', () {
    const fraction = Offset(0.25, 0.5);

    test('keeps the place on a page that still shows', () {
      expect(
        placeAfter(page: 3, fraction: fraction, shownAfter: {2, 3}),
        (page: 3, fraction: fraction),
      );
      expect(
        placeAfter(page: 3, fraction: fraction, shownAfter: null),
        (page: 3, fraction: fraction),
      );
    });

    test('goes to the top of the nearest page shown, the earlier on a tie', () {
      expect(
        placeAfter(page: 1, fraction: fraction, shownAfter: {4, 9}),
        (page: 4, fraction: const Offset(0.25, 0)),
      );
      expect(
        placeAfter(page: 6, fraction: fraction, shownAfter: {8, 4}),
        (page: 4, fraction: const Offset(0.25, 0)),
      );
      expect(
        placeAfter(page: 7, fraction: fraction, shownAfter: {2, 8}),
        (page: 8, fraction: const Offset(0.25, 0)),
      );
    });
  });
}
