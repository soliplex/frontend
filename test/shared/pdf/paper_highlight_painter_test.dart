import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/shared/pdf/paper_highlight_painter.dart';

/// Records the paths drawn and the paints they were drawn with.
class _RecordingCanvas extends Fake implements Canvas {
  final draws = <(Path, Paint)>[];

  @override
  void drawPath(Path path, Paint paint) => draws.add((path, paint));
}

void main() {
  const a = Rect.fromLTWH(10, 10, 40, 8);
  const b = Rect.fromLTWH(10, 30, 40, 8);

  test('draws nothing without matches', () {
    final canvas = _RecordingCanvas();
    paintPaperMatches(canvas, others: const [], active: const []);
    expect(canvas.draws, isEmpty);
  });

  test('fills the other matches once, multiplied, in the match colour', () {
    final canvas = _RecordingCanvas();
    paintPaperMatches(canvas, others: const [a, b], active: const []);

    final (path, paint) = canvas.draws.single;
    expect(paint.color.toARGB32(), PaperHighlights.match.toARGB32());
    expect(paint.blendMode, BlendMode.multiply);
    expect(paint.style, PaintingStyle.fill);
    expect(path.contains(a.center), isTrue);
    expect(path.contains(b.center), isTrue);
  });

  test('fills the current match, then outlines it', () {
    final canvas = _RecordingCanvas();
    paintPaperMatches(canvas, others: const [b], active: const [a]);

    expect(canvas.draws, hasLength(3));
    final (_, others) = canvas.draws[0];
    final (activePath, fill) = canvas.draws[1];
    final (outlinePath, outline) = canvas.draws[2];
    expect(others.color.toARGB32(), PaperHighlights.match.toARGB32());
    expect(fill.color.toARGB32(), PaperHighlights.activeMatch.toARGB32());
    expect(fill.blendMode, BlendMode.multiply);
    expect(activePath.contains(a.center), isTrue);
    expect(activePath.contains(b.center), isFalse);
    expect(outline.style, PaintingStyle.stroke);
    expect(outline.strokeWidth, 2);
    expect(outline.color.toARGB32(),
        PaperHighlights.activeMatchOutline.toARGB32());
    expect(outline.blendMode, BlendMode.srcOver);
    expect(identical(outlinePath, activePath), isTrue);
  });

  test('reaches a little past the glyphs', () {
    final canvas = _RecordingCanvas();
    paintPaperMatches(canvas, others: const [a], active: const []);

    final (path, _) = canvas.draws.single;
    expect(path.getBounds(), a.inflate(1));
  });
}
