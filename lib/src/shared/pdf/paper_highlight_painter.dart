import 'dart:ui';

import 'package:soliplex_design/soliplex_design.dart';

/// Paints search matches on a page: [others] in [PaperHighlights.match], the
/// current one's rectangles, [active], in [PaperHighlights.activeMatch] with
/// an outline.
///
/// The fills multiply, as their tokens were measured: ink stays dark and
/// paper takes the fill's colour, where pdfrx's own match painter tints the
/// ink along with the paper. Each set is one path, so a match whose
/// rectangles overlap — characters on a line — does not stack its tint.
///
/// Rectangles are in the canvas's coordinates, already placed on the page.
void paintPaperMatches(
  Canvas canvas, {
  required Iterable<Rect> others,
  required Iterable<Rect> active,
}) {
  _fill(canvas, others, PaperHighlights.match);
  final activePath = _fill(canvas, active, PaperHighlights.activeMatch);
  if (activePath == null) return;
  _outline(canvas, activePath);
}

/// Paints a cited passage on a page: its [context] in
/// [PaperHighlights.context], then its [anchor] as the current match is
/// painted, in [PaperHighlights.activeMatch] with an outline.
///
/// Fills multiply, as in [paintPaperMatches]. Rectangles are in the canvas's
/// coordinates, already placed on the page.
void paintPaperPassage(
  Canvas canvas, {
  required Iterable<Rect> context,
  required Iterable<Rect> anchor,
}) {
  _fill(canvas, context, PaperHighlights.context);
  final anchorPath = _fill(canvas, anchor, PaperHighlights.activeMatch);
  if (anchorPath == null) return;
  _outline(canvas, anchorPath);
}

void _outline(Canvas canvas, Path path) => canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _outlineWidth
        ..color = PaperHighlights.activeMatchOutline,
    );

/// The outline's width in logical pixels, as `PaperHighlights` specifies.
const _outlineWidth = 2.0;

/// The marks reach a little past the glyphs, so the fill frames the text
/// rather than cutting through ascenders.
const _bleed = 1.0;

Path? _fill(Canvas canvas, Iterable<Rect> rects, Color color) {
  if (rects.isEmpty) return null;
  final path = Path();
  for (final rect in rects) {
    path.addRect(rect.inflate(_bleed));
  }
  canvas.drawPath(
    path,
    Paint()
      ..color = color
      ..blendMode = BlendMode.multiply,
  );
  return path;
}
