import 'dart:ui';

import 'package:xml/xml.dart';
import 'package:xml/xml_events.dart';

/// CSS's default size for a replaced element: what Chrome gives an SVG image
/// for a side its root does not state.
const _defaultWidth = 300.0;
const _defaultHeight = 150.0;

/// A CSS number: no trailing `.`, no `Infinity` or `NaN`, which
/// [double.tryParse] would accept.
const _cssNumber = r'[+-]?(?:\d+(?:\.\d+)?|\.\d+)(?:e[+-]?\d+)?';

final _length = RegExp(
  '^($_cssNumber)(px|pt|pc|in|cm|mm|q|em|rem)?\$',
  caseSensitive: false,
);

/// Pixels per unit: CSS's fixed ratios, and 16 for `em` and `rem`, the font
/// size Chrome gives an SVG drawn as an image.
const _pixelsPerUnit = {
  'px': 1.0,
  'pt': 96 / 72,
  'pc': 16.0,
  'in': 96.0,
  'cm': 96 / 2.54,
  'mm': 96 / 25.4,
  'q': 96 / 101.6,
  'em': 16.0,
  'rem': 16.0,
};
final _nonzeroDigit = RegExp(r'[1-9]');
// SVG viewBox numbers permit a decimal point after an integer even when
// there are no fractional digits. CSS dimension tokens use _cssNumber.
final _viewBoxNumber = RegExp(
  r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$',
);
final _viewBoxSeparator = RegExp(r'\s*,\s*|\s+');

/// The size an SVG's picture is laid out at, read from its root element's
/// `width`, `height` and `viewBox` attributes.
///
/// A side is usable when it is a positive CSS number, unitless or in an
/// absolute unit (`px`, `pt`, `pc`, `in`, `cm`, `mm`, `Q`), resolved at CSS's
/// ratios, or in `em` or `rem`, at the 16 px Chrome gives an SVG image. A
/// percentage, a font- or viewport-relative unit (`ex`, `ch`, `vw`), or a
/// value CSS does not parse is not. A
/// viewBox is usable when it is four numbers, separated by whitespace or
/// commas, with a positive width and height. CSS that sizes the root (its
/// `style`, or a `<style>` rule) is ignored, as Chrome ignores it for an SVG
/// drawn as an image.
///
/// An explicit zero root side suppresses painting, so it returns [Size.zero]
/// even when a viewBox is present. Otherwise the first drawable size wins:
///
/// 1. both sides;
/// 2. one side, with the other derived from the viewBox's ratio;
/// 3. the viewBox's size;
/// 4. the usable sides, with 300 for a missing width and 150 for a missing
///    height, as Chrome sizes a root without a viewBox;
/// 5. 300 x 150.
///
/// A size is drawable when both sides and their ratio are finite and
/// positive: deriving a side, or the ratio of two finite sides, can overflow
/// or underflow, and the layout divides by them. Only the root's start tag
/// is read, so a large SVG is not parsed whole, and an SVG that is malformed
/// after it still has a size. One with no root to read gets 300 x 150.
Size svgRootSize(String svg) {
  final root = _rootStartTag(svg);
  if (root == null) return const Size(_defaultWidth, _defaultHeight);
  String? attribute(String name) =>
      root.attributes.where((a) => a.name == name).firstOrNull?.value;
  final width = _parseLength(attribute('width'));
  final height = _parseLength(attribute('height'));
  if (width == 0 || height == 0) return Size.zero;
  final viewBox = _parseViewBox(attribute('viewBox'));
  return _candidates(width, height, viewBox).firstWhere(
    _isDrawable,
    orElse: () => const Size(_defaultWidth, _defaultHeight),
  );
}

Iterable<Size> _candidates(double? width, double? height, Size? viewBox) sync* {
  if (width != null && height != null) yield Size(width, height);
  if (viewBox != null) {
    final ratio = viewBox.width / viewBox.height;
    if (width != null) yield Size(width, width / ratio);
    if (height != null) yield Size(height * ratio, height);
    yield viewBox;
  }
  yield Size(width ?? _defaultWidth, height ?? _defaultHeight);
}

bool _isDrawable(Size size) {
  final ratio = size.width / size.height;
  return _isPositiveFinite(size.width) &&
      _isPositiveFinite(size.height) &&
      _isPositiveFinite(ratio);
}

bool _isPositiveFinite(double value) => value.isFinite && value > 0;

XmlStartElementEvent? _rootStartTag(String svg) {
  try {
    return parseEvents(svg).whereType<XmlStartElementEvent>().firstOrNull;
  } on XmlException {
    return null;
  }
}

double? _parseLength(String? value) {
  if (value == null) return null;
  final match = _length.firstMatch(value.trim());
  if (match == null) return null;
  final unit = (match.group(2) ?? 'px').toLowerCase();
  final number = match.group(1)!;
  // Check the significand so a tiny nonzero length that underflows is
  // treated as unusable rather than as an explicit zero.
  final significand = number.toLowerCase().split('e').first;
  if (!_nonzeroDigit.hasMatch(significand)) return 0;
  final length = double.parse(number) * _pixelsPerUnit[unit]!;
  return _isPositiveFinite(length) ? length : null;
}

Size? _parseViewBox(String? value) {
  if (value == null) return null;
  final parts = value.trim().split(_viewBoxSeparator);
  if (parts.length != 4 || !parts.every(_viewBoxNumber.hasMatch)) return null;
  final size = Size(double.parse(parts[2]), double.parse(parts[3]));
  return _isPositiveFinite(size.width) && _isPositiveFinite(size.height)
      ? size
      : null;
}
