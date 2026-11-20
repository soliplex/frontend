import 'package:vector_graphics_compiler/vector_graphics_compiler.dart';

/// Asks flutter_svg's own parser whether it can take a style value, so a
/// value it would throw on, or warn about, is left out rather than failing
/// the whole SVG.
///
/// [passes] tries a value alone in a one-element SVG, with warnings treated
/// as errors; a value flutter_svg ignores silently passes it (see [colours]
/// for a fill or stroke), and so does one it rejects only through an
/// assert, as in the release builds users run. Answers are remembered per
/// check and value. One whose reading depends on the drawing around it (a
/// percentage of an unknown viewport) can pass here and still fail in the
/// whole SVG.
class ValueCheck {
  /// Past this many checks, any other value passes unchecked: each check is a
  /// parse, and an SVG of many distinct values (a scatter plot colouring each
  /// point) would otherwise hold the UI thread. Refusing them instead would
  /// strip values the SVG as written draws. One that then throws is caught by
  /// `SvgBody`, which draws the SVG as written; a colour flutter_svg ignores
  /// is written.
  static const _maxChecks = 4096;

  final _answers = <(String, String, String), bool>{};

  /// Whether flutter_svg reads [value] as a colour for [property], rather
  /// than ignoring it silently and painting the parent's colour: true for a
  /// property other than `fill` and `stroke`, and for a value that names no
  /// colour of its own (`none`, `inherit`, `currentColor`, a `url()`
  /// reference). Tried under two parents of different colours: a value
  /// flutter_svg ignores paints each parent's.
  bool colours(String property, String value) {
    if (property != 'fill' && property != 'stroke') return true;
    // inherit paints the parent's colour, as an ignored value does, but on
    // purpose. The other values naming no colour paint none or their own.
    if (value.trim().toLowerCase() == 'inherit') return true;
    final key = ('colour', property, value);
    if (_answers[key] case final answer?) return answer;
    if (_answers.length >= _maxChecks) return true;
    return _answers[key] = _painted(property, value, _parent) != _parent ||
        _painted(property, value, _otherParent) != _otherParent;
  }

  static const _parent = 0xff010203;
  static const _otherParent = 0xff040506;

  /// The colour flutter_svg paints a shape with [property]: [value] under a
  /// parent whose [property] is [parent]; null where it paints none or
  /// cannot parse it.
  static int? _painted(String property, String value, int parent) {
    final hex = (parent & 0xffffff).toRadixString(16).padLeft(6, '0');
    try {
      final paints = parseWithoutOptimizers(
        '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
        '<g $property="#$hex"><rect width="10" height="10" '
        'style="${_attribute('$property:$value')}"/></g></svg>',
      ).paints;
      final paint = paints.isEmpty ? null : paints.first;
      final colour =
          property == 'fill' ? paint?.fill?.color : paint?.stroke?.color;
      return colour?.value;
    } catch (_) {
      // Asked only of a value passes took, so a throw here (an assert, in
      // debug builds) keeps it, as passes did.
      return null;
    }
  }

  /// Whether flutter_svg takes [property]: [value] on a [tag] element.
  bool passes(String tag, String property, String value) {
    final key = (tag, property, value);
    if (_answers[key] case final answer?) return answer;
    if (_answers.length >= _maxChecks) return true;
    return _answers[key] = _parses(
      '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">'
      '<$tag style="${_attribute('$property:$value')}"/></svg>',
    );
  }

  static bool _parses(String svg) {
    try {
      parseWithoutOptimizers(svg, warningsAsErrors: true);
      return true;
    } on AssertionError {
      // Asserts run only in debug builds; the value passes, as it does in
      // the release builds users run, so the answer is the same in both.
      return true;
    } catch (_) {
      // Any other failure means flutter_svg would throw on the value, or
      // warn and ignore it; which one does not matter here.
      return false;
    }
  }

  static String _attribute(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('"', '&quot;')
      .replaceAll('<', '&lt;');
}
