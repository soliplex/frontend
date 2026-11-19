import 'package:flutter/painting.dart';

/// Highlight colours for marks drawn on a document page: a text selection, a
/// search match, a cited passage.
///
/// Fixed rather than themed. A page is paper — white, with dark ink — in the
/// light and the dark theme alike, so a colour picked from the app's palette
/// would sit on the wrong background in one of them. Each value states the
/// blend mode it was measured with; painting it any other way voids its
/// contrast:
///
/// - text under any mark stays at WCAG AA (4.5:1) or better against the
///   marked paper;
/// - a mark that has to be found on the page by its shape alone — a selection
///   handle, the active match's outline — reaches 3:1 against white.
///
/// The tests in `test/tokens/paper_highlights_test.dart` hold every value to
/// those bars.
abstract final class PaperHighlights {
  /// A text selection: blue at 30%, painted with normal blending over the
  /// page, ink included.
  ///
  /// Selection handles are drawn from the same hue at 70% (resting) and full
  /// opacity (dragged), which is why the hue is darker than a typical
  /// selection blue: at 70% over white it still clears 3:1.
  static const selection = Color(0x4D0B57D0);

  /// A match that is not the current one — another search hit, another cited
  /// passage. Opaque; painted with [BlendMode.multiply], so ink stays dark
  /// and paper takes exactly this colour.
  static const match = Color(0xFFFDE68A);

  /// The current match. Opaque; painted with [BlendMode.multiply], like
  /// [match], and outlined with [activeMatchOutline].
  static const activeMatch = Color(0xFFFCD34D);

  /// The outline that sets the current match apart from paper and from the
  /// other matches, stroked 2 logical pixels wide with normal blending. The
  /// fills alone are too pale to find by shape against white.
  static const activeMatchOutline = Color(0xFFB45309);
}
