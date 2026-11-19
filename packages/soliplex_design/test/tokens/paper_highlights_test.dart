import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_design/src/brand/contrast.dart';

const _paper = Color(0xFFFFFFFF);
const _ink = Color(0xFF000000);

/// [color] multiplied onto [base], channel by channel, as
/// [BlendMode.multiply] composites an opaque source.
Color _multiply(Color color, Color base) => Color.from(
      alpha: 1,
      red: color.r * base.r,
      green: color.g * base.g,
      blue: color.b * base.b,
    );

void main() {
  group('PaperHighlights', () {
    group('selection, painted with normal blending over ink and paper', () {
      test('keeps ink legible: AA against the selected paper', () {
        const selection = PaperHighlights.selection;
        expect(
          contrastRatio(
            Color.alphaBlend(selection, _ink),
            Color.alphaBlend(selection, _paper),
          ),
          greaterThanOrEqualTo(4.5),
        );
      });

      test('a resting handle (the hue at 70%) is findable against paper', () {
        final handle = PaperHighlights.selection.withValues(alpha: 0.7);
        expect(
          contrastRatio(Color.alphaBlend(handle, _paper), _paper),
          greaterThanOrEqualTo(3),
        );
      });

      test('a dragged handle (the hue opaque) is findable against paper', () {
        final handle = PaperHighlights.selection.withValues(alpha: 1);
        expect(contrastRatio(handle, _paper), greaterThanOrEqualTo(3));
      });
    });

    group('matches, painted with multiply', () {
      for (final (name, fill) in [
        ('match', PaperHighlights.match),
        ('activeMatch', PaperHighlights.activeMatch),
      ]) {
        test('$name is opaque, which multiply assumes', () {
          expect(fill.a, 1);
        });

        test('$name keeps ink legible: AA against the marked paper', () {
          expect(
            contrastRatio(_multiply(fill, _ink), _multiply(fill, _paper)),
            greaterThanOrEqualTo(4.5),
          );
        });
      }

      test('the active outline is findable against paper', () {
        expect(
          contrastRatio(PaperHighlights.activeMatchOutline, _paper),
          greaterThanOrEqualTo(3),
        );
      });

      test('the active outline sets the active fill apart from the others', () {
        expect(
          contrastRatio(
            PaperHighlights.activeMatchOutline,
            PaperHighlights.match,
          ),
          greaterThanOrEqualTo(3),
        );
      });
    });
  });
}
