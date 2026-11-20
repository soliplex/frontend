import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/svg_root_size.dart';

/// An SVG whose root carries [attributes].
String _svg(String attributes) =>
    '<svg xmlns="http://www.w3.org/2000/svg" $attributes></svg>';

/// CSS's default size for a replaced element, which Chrome gives an SVG
/// image whose root states no size.
const _default = Size(300, 150);

void _expectValid(Size size) {
  expect(size.width.isFinite && size.width > 0, isTrue, reason: '$size');
  expect(size.height.isFinite && size.height > 0, isTrue, reason: '$size');
  final ratio = size.width / size.height;
  expect(ratio.isFinite && ratio > 0, isTrue, reason: '$size');
}

void main() {
  group('svgRootSize', () {
    test('takes width and height when both are usable', () {
      expect(
        svgRootSize(_svg('width="120" height="80" viewBox="0 0 10 10"')),
        const Size(120, 80),
      );
    });

    test('reads px in any case, signs, exponents and surrounding space', () {
      expect(svgRootSize(_svg('width="120px" height="80PX"')),
          const Size(120, 80));
      expect(svgRootSize(_svg('width="+1.2e2" height=" .5 "')),
          const Size(120, 0.5));
      expect(svgRootSize(_svg('width="\n120px " height="80"')),
          const Size(120, 80));
    });

    test('takes the viewBox size when neither side is usable', () {
      expect(svgRootSize(_svg('viewBox="4 4 754 187"')), const Size(754, 187));
    });

    test('ignores a percentage, as mermaid writes it, for the viewBox', () {
      expect(
        svgRootSize(_svg('width="100%" style="max-width: 754px;" '
            'viewBox="4 4 754 187"')),
        const Size(754, 187),
      );
    });

    test('derives the other side from the viewBox ratio', () {
      expect(svgRootSize(_svg('width="200" viewBox="0 0 100 50"')),
          const Size(200, 100));
      expect(svgRootSize(_svg('height="200" viewBox="0 0 100 50"')),
          const Size(400, 200));
    });

    test('resolves absolute units as Chrome does, in any case', () {
      // 1 inch in each unit; Chrome gives every one 96 px.
      for (final length in [
        '72pt',
        '6pc',
        '1in',
        '2.54cm',
        '25.4mm',
        '101.6Q',
        '1IN',
      ]) {
        final size = svgRootSize(_svg('width="$length" height="$length"'));
        expect(size.width, closeTo(96, 1e-9), reason: length);
        expect(size.height, closeTo(96, 1e-9), reason: length);
      }
    });

    test('resolves em and rem at 16 px, as Chrome does for an image', () {
      expect(
          svgRootSize(_svg('width="10em" height="5rem"')), const Size(160, 80));
    });

    test('takes the sides over the viewBox when given in points', () {
      expect(
        svgRootSize(
            _svg('width="460.8pt" height="345.6pt" viewBox="0 0 460.8 345.6"')),
        const Size(614.4, 460.8),
      );
    });

    test('treats font- and viewport-relative units as unusable', () {
      // Chrome sizes ex from the font, and vw and vh to nothing.
      for (final length in ['12ex', '10vw', '10vh', '5ch']) {
        expect(
          svgRootSize(_svg('width="$length" viewBox="0 0 10 5"')),
          const Size(10, 5),
          reason: length,
        );
      }
    });

    test('distinguishes explicit zero from parser underflow', () {
      expect(svgRootSize(_svg('width="0" viewBox="0 0 10 5"')), Size.zero);
      expect(svgRootSize(_svg('height="0e5pt" viewBox="0 0 10 5"')), Size.zero);
      expect(
        svgRootSize(_svg('width="1e-400px" viewBox="0 0 10 5"')),
        const Size(10, 5),
      );
    });

    test('rejects lengths CSS does not parse', () {
      for (final length in [
        '100.',
        '100 px',
        'Infinity',
        'NaN',
        '',
        'abc',
        '-5',
      ]) {
        // Read as 100, the width would give 100 x 50, not the viewBox's size.
        expect(
          svgRootSize(_svg('width="$length" viewBox="0 0 10 5"')),
          const Size(10, 5),
          reason: length,
        );
      }
    });

    test('defaults each side Chrome defaults when there is no viewBox', () {
      expect(svgRootSize(_svg('')), _default);
      expect(svgRootSize(_svg('width="100"')), const Size(100, 150));
      expect(svgRootSize(_svg('height="80"')), const Size(300, 80));
      expect(svgRootSize(_svg('width="50%" height="50%"')), _default);
    });

    test('reads a viewBox separated by commas and spaces', () {
      expect(
          svgRootSize(_svg('viewBox=" 0, 0 ,100 ,50 "')), const Size(100, 50));
      expect(svgRootSize(_svg('viewBox="0,0,1e2,50"')), const Size(100, 50));
    });

    test('reads trailing decimal points in SVG viewBox numbers', () {
      expect(
        svgRootSize(_svg('viewBox="0 0 100. 100."')),
        const Size(100, 100),
      );
      expect(
        svgRootSize(_svg('width="100." viewBox="-1. +2. 2.E2 .5e2"')),
        const Size(200, 50),
      );
    });

    test('rejects a viewBox that is not four numbers with a positive size', () {
      for (final viewBox in [
        '0 0 100',
        '0 0 100 50 7',
        '0 0 -100 50',
        '0 0 100 0',
        '0 0 100px 50',
        '0 0 Infinity 50',
      ]) {
        expect(
          svgRootSize(_svg('width="200" viewBox="$viewBox"')),
          const Size(200, 150),
          reason: viewBox,
        );
      }
    });

    test('ignores CSS that sizes the root, as Chrome does for an image', () {
      expect(
        svgRootSize(
          '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" '
          'style="width:200px;height:100px">'
          '<style>svg{width:200px;height:100px}</style></svg>',
        ),
        const Size(100, 100),
      );
    });

    test('finds the root after a declaration, comment and doctype', () {
      expect(
        svgRootSize(
          '<?xml version="1.0"?>\n<!-- made by hand -->\n'
          '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" '
          '"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">\n'
          '<svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">'
          '</svg>',
        ),
        const Size(120, 80),
      );
    });

    test('reads the root even when the rest of the SVG is malformed', () {
      expect(
        svgRootSize('<svg width="120" height="80"><g><rect></svg>'),
        const Size(120, 80),
      );
    });

    test('defaults when there is no root to read', () {
      expect(svgRootSize('not xml at all'), _default);
      expect(svgRootSize('<<svg width="120" height="80">'), _default);
      expect(svgRootSize(''), _default);
    });

    group('extreme finite values', () {
      test('a derived side that overflows falls back to the viewBox size', () {
        final size =
            svgRootSize(_svg('width="1e300" viewBox="0 0 1e-10 1e300"'));
        _expectValid(size);
        expect(size, const Size(1e-10, 1e300));
      });

      test('a derived side that underflows to zero falls back', () {
        // The viewBox's own ratio overflows too, so the width is kept and the
        // height defaults.
        final size =
            svgRootSize(_svg('width="1e-300" viewBox="0 0 1e300 1e-10"'));
        _expectValid(size);
        expect(size, const Size(1e-300, 150));
      });

      test('two usable sides whose ratio overflows fall back', () {
        final size = svgRootSize(_svg('width="1e300" height="1e-300"'));
        _expectValid(size);
        expect(size, _default);
      });

      test('a viewBox whose ratio overflows is not used', () {
        final size = svgRootSize(_svg('viewBox="0 0 1e300 1e-300"'));
        _expectValid(size);
        expect(size, _default);
      });

      test('the largest and smallest doubles stay valid', () {
        for (final attributes in [
          'width="${double.maxFinite}" height="${double.maxFinite}"',
          'width="${double.minPositive}" height="${double.minPositive}"',
          'viewBox="0 0 ${double.maxFinite} 1"',
          'viewBox="0 0 1 ${double.minPositive}"',
          'width="${double.maxFinite}" viewBox="0 0 1 ${double.maxFinite}"',
          'height="${double.minPositive}" '
              'viewBox="0 0 ${double.maxFinite} 1"',
        ]) {
          _expectValid(svgRootSize(_svg(attributes)));
        }
      });
    });
  });
}
