// The lookbehind starts a name only at its first letter; without it, a long
// run of letters is retried from each one, in time quadratic in its length.
final _transformFunction = RegExp(r'(?<![a-zA-Z])([a-zA-Z]+)\(([^()]*)\)');

/// [transform], a CSS transform, in the SVG `transform` attribute's syntax,
/// turning about [origin], a CSS `transform-origin` as written. Only the
/// functions generated SVGs use are taken: `translate` (and its X and Y
/// forms) in `px`, `rotate` in `deg`, `scale` (and its X and Y forms) and
/// `none`. Null for any other, another unit, or an origin that is not two
/// `px` or unitless lengths (keywords and percentages are relative to a
/// reference box whose size this code does not know).
String? svgTransform(String transform, String origin) {
  final point = _origin(origin);
  if (point == null) return null;
  final value = transform.trim();
  if (value.toLowerCase() == 'none') return 'translate(0)';
  final parts = <String>[];
  var end = 0;
  for (final match in _transformFunction.allMatches(value)) {
    if (value.substring(end, match.start).trim().isNotEmpty) return null;
    end = match.end;
    final arguments = match
        .group(2)!
        .split(RegExp(r'\s*,\s*|\s+'))
        .where((argument) => argument.isNotEmpty)
        .toList();
    final part = _svgTransformFunction(match.group(1)!, arguments);
    if (part == null) return null;
    parts.add(part);
  }
  if (parts.isEmpty || value.substring(end).trim().isNotEmpty) return null;
  final (x, y) = point;
  if (x == 0 && y == 0) return parts.join(' ');
  return [
    'translate(${_formatted(x)} ${_formatted(y)})',
    ...parts,
    'translate(${_formatted(-x)} ${_formatted(-y)})',
  ].join(' ');
}

/// One CSS transform function [name] over [arguments] in the attribute's
/// syntax, or null when this code writes no equivalent for it.
String? _svgTransformFunction(String name, List<String> arguments) {
  List<double>? each(double? Function(String) parse) {
    final values = arguments.map(parse).toList();
    return values.contains(null) ? null : values.cast<double>();
  }

  final lengths = each(_pixels);
  final numbers = each(_plainNumber);
  final angles = each(_degrees);

  return switch ((name.toLowerCase(), arguments.length)) {
    ('translate', 1 || 2) when lengths != null =>
      'translate(${_formatted(lengths[0])} '
          '${_formatted(lengths.length > 1 ? lengths[1] : 0)})',
    ('translatex', 1) when lengths != null =>
      'translate(${_formatted(lengths[0])} 0)',
    ('translatey', 1) when lengths != null =>
      'translate(0 ${_formatted(lengths[0])})',
    ('scale', 1 || 2) when numbers != null =>
      'scale(${_formatted(numbers[0])} ${_formatted(numbers.last)})',
    ('scalex', 1) when numbers != null => 'scale(${_formatted(numbers[0])} 1)',
    ('scaley', 1) when numbers != null => 'scale(1 ${_formatted(numbers[0])})',
    ('rotate', 1) when angles != null => 'rotate(${_formatted(angles[0])})',
    _ => null,
  };
}

/// A CSS number, with no exponent.
final _number = RegExp(r'^-?(?:\d+\.?\d*|\.\d+)$');

// A number too large for a double parses to infinity, which no transform
// can be written with.
double? _plainNumber(String text) {
  if (!_number.hasMatch(text)) return null;
  final number = double.parse(text);
  return number.isFinite ? number : null;
}

/// [text] as pixels: a number in `px`, or `0`; with [unitless], any number
/// with no unit, as a presentation attribute may be written.
double? _pixels(String text, {bool unitless = false}) {
  final number = _plainNumber(text);
  if (number != null) return unitless || number == 0 ? number : null;
  if (!text.endsWith('px')) return null;
  return _plainNumber(text.substring(0, text.length - 2));
}

/// [text] as degrees: an angle in `deg`, or `0`.
double? _degrees(String text) {
  if (_plainNumber(text) == 0) return 0;
  if (!text.toLowerCase().endsWith('deg')) return null;
  return _plainNumber(text.substring(0, text.length - 3));
}

/// [value] written without a trailing `.0`.
String _formatted(double value) => value == value.roundToDouble()
    ? value.round().toString()
    : value.toString();

/// [origin], a CSS `transform-origin`, as a point in pixels: two lengths and
/// an optional zero depth.
(double, double)? _origin(String origin) {
  final parts = origin.trim().split(RegExp(r'\s+'));
  if (parts.length < 2 || parts.length > 3) return null;
  final x = _pixels(parts[0], unitless: true);
  final y = _pixels(parts[1], unitless: true);
  if (x == null || y == null) return null;
  if (parts.length == 3 && _pixels(parts[2], unitless: true) != 0) return null;
  return (x, y);
}
