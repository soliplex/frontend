import 'package:markdown/markdown.dart' as md;

/// Inline LaTeX syntax that recognises only unambiguous math delimiters:
/// `$$…$$` and `\[…\]` (display), `$…$` and `\(…\)` (text).
///
/// Replaces `LatexInlineSyntax` from `flutter_markdown_plus_latex`, which also
/// treats `( … )` and `[ … ]` — a bracket followed by a space — as math. Prose
/// such as `( Note 2&5 )` then reaches the TeX parser and renders as a parser
/// error in place of the text. The package's `\ce{…}` and `\pu{…}` delimiters
/// are dropped too: `flutter_math_fork` implements neither macro, so they could
/// only ever render an error.
///
/// Emits the same `latex` element, with the same `MathStyle` attribute, that
/// `LatexElementBuilder` consumes.
class LatexInlineSyntax extends md.InlineSyntax {
  LatexInlineSyntax() : super(_pattern);

  static const _delimiters = [
    (left: r'$$', right: r'$$', display: true),
    (left: r'$', right: r'$', display: false),
    (left: r'\(', right: r'\)', display: false),
    (left: r'\[', right: r'\]', display: true),
  ];

  // Each delimiter pair encloses a non-empty, single-line body in which a
  // backslash escapes the next character. The closing delimiter must be
  // followed by whitespace, punctuation, or the end of the input, so a lone
  // `$` in prose (`costs $5 and $10`) does not open a span.
  static final String _pattern = '(?:${_delimiters.map((d) {
    final left = RegExp.escape(d.left);
    final right = RegExp.escape(d.right);
    return '$left((?:\\\\.|[^\\\\\\n])+?)$right';
  }).join('|')})(?=[\\s?!.,:？！。，：]|\$)';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    for (var i = 0; i < _delimiters.length; i++) {
      final equation = match.group(i + 1);
      if (equation == null) continue;
      parser.addNode(
        md.Element.text('latex', equation)
          ..attributes['MathStyle'] =
              _delimiters[i].display ? 'display' : 'text',
      );
      return true;
    }
    return false;
  }
}
