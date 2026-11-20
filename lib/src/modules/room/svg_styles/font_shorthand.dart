/// A `font` shorthand's size as CSS writes it: a number with a unit or `%`,
/// or a size keyword.
final _fontSize = RegExp(
  r'^(?:[\d.]+(?:[a-z]+|%)|(?:xx?-)?(?:small|large)|medium|larger|smaller)$',
  caseSensitive: false,
);

/// The keywords a `font` shorthand may put before its size, other than a
/// weight: a style or a variant, neither of which flutter_svg reads.
const _fontKeywords = {'normal', 'italic', 'oblique', 'small-caps'};

/// The longhands of a `font` shorthand, `[style] [variant] [weight]
/// size[/line-height] family`, that flutter_svg reads: the weight
/// (`normal` when the shorthand leaves it out, as CSS resets it), the size
/// and the family. Null for another form, such as a system font (`caption`).
Map<String, String>? fontLonghands(String value) {
  var weight = 'normal';
  // A line height is written beside the size, with or without spaces:
  // `14px/1.4`, `14px / 1.4`.
  final text = value.split('/').map((part) => part.trim()).join('/');
  for (final match in _token.allMatches(text)) {
    final token = match[0]!;
    final slash = token.indexOf('/');
    final size = slash < 0 ? token : token.substring(0, slash);
    if (_fontSize.hasMatch(size)) {
      final family = text.substring(match.end).trimLeft();
      if (family.isEmpty) return null;
      return {
        'font-weight': weight,
        'font-size': size,
        'font-family': family,
      };
    }
    final keyword = token.toLowerCase();
    if (_numericWeight.hasMatch(keyword) ||
        const {'bold', 'bolder', 'lighter'}.contains(keyword)) {
      weight = keyword;
    } else if (!_fontKeywords.contains(keyword)) {
      return null;
    }
  }
  return null;
}

final _token = RegExp(r'\S+');

final _numericWeight = RegExp(r'^\d+$');
