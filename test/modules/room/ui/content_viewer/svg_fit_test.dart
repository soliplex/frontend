import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/content_viewer/svg_fit.dart';

/// What an inline SvgBody picture is given: the column's width, stretched,
/// and at most 400 high.
const _inline = BoxConstraints(minWidth: 600, maxWidth: 600, maxHeight: 400);

/// The zoom dialog and the workdir viewer fill their space.
final _dialog = BoxConstraints.tight(const Size(800, 600));
final _workdir = BoxConstraints.tight(const Size(1000, 700));

void _expectFinitePictureInBox(
  ({Size box, Size picture}) fit, {
  required String reason,
}) {
  final (:box, :picture) = fit;
  for (final side in [box.width, box.height, picture.width, picture.height]) {
    expect(side.isFinite, isTrue, reason: '$reason: $fit');
    expect(side >= 0, isTrue, reason: '$reason: $fit');
  }
  expect(picture.width <= box.width, isTrue, reason: '$reason: $fit');
  expect(picture.height <= box.height, isTrue, reason: '$reason: $fit');
}

void main() {
  group('fitSvg', () {
    test('keeps a size that fits loose constraints', () {
      final fit = fitSvg(
        const Size(120, 80),
        const BoxConstraints(maxWidth: 600, maxHeight: 400),
      );
      expect(fit.box, const Size(120, 80));
      expect(fit.picture, const Size(120, 80));
    });

    test('scales a picture to the inline column width, keeping its shape', () {
      final fit = fitSvg(const Size(120, 60), _inline);
      expect(fit.box, const Size(600, 300));
      expect(fit.picture, const Size(600, 300));
    });

    test('caps a tall picture at the inline height, keeping its shape', () {
      final fit = fitSvg(const Size(300, 1000), _inline);
      expect(fit.box, const Size(600, 400));
      expect(fit.picture, const Size(120, 400));
    });

    test('scales a picture up to contain it in a tight box', () {
      final square = fitSvg(const Size(100, 100), _dialog);
      expect(square.box, const Size(800, 600));
      expect(square.picture, const Size(600, 600));

      final wide = fitSvg(const Size(1200, 300), _dialog);
      expect(wide.box, const Size(800, 600));
      expect(wide.picture, const Size(800, 200));
    });

    test('gives a finite picture inside its box for extreme sizes', () {
      // applyBoxFit multiplies before dividing: a 1e308 square in a tight
      // 800 x 600 box comes out infinitely wide.
      const sizes = [
        Size(1e308, 1e308),
        Size(double.maxFinite, double.maxFinite),
        Size(double.maxFinite, 1),
        Size(1, double.maxFinite),
        Size(double.minPositive, 1),
        Size(1, double.minPositive),
        Size(double.minPositive, double.minPositive),
        Size(1e-10, 1e300),
        Size(1e-300, 150),
      ];
      final shapes = {
        'inline': _inline,
        'dialog': _dialog,
        'workdir': _workdir
      };
      for (final size in sizes) {
        for (final MapEntry(key: shape, value: constraints) in shapes.entries) {
          _expectFinitePictureInBox(
            fitSvg(size, constraints),
            reason: '$size in $shape',
          );
        }
      }
    });

    test('contains a 1e308 square in a tight box at the box height', () {
      final fit = fitSvg(const Size(1e308, 1e308), _dialog);
      expect(fit.picture, const Size(600, 600));
    });
  });
}
