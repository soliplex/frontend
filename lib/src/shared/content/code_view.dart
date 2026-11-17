import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:soliplex_design/soliplex_design.dart';

const _rootKey = 'root';

// Flutter cannot render a tab stop (flutter/flutter#50087), so tabs become
// spaces before highlighting.
const _tabWidth = 8;

/// Highlighted [code] as spans coloured by [theme]. A [language] the
/// highlighter does not know is rendered as plain text.
List<InlineSpan> highlightSpans(
  String code,
  String language,
  Map<String, TextStyle> theme,
) {
  final nodes = highlight.parse(code, language: language).nodes ?? const [];
  return _convert(nodes, theme);
}

List<TextSpan> _convert(List<Node> nodes, Map<String, TextStyle> theme) {
  return [
    for (final node in nodes)
      if (node.value != null)
        TextSpan(
          text: node.value,
          style: node.className == null ? null : theme[node.className!],
        )
      else if (node.children != null)
        TextSpan(
          children: _convert(node.children!, theme),
          style: node.className == null ? null : theme[node.className!],
        ),
  ];
}

/// The monospace style shared by every code surface.
TextStyle codeTextStyle(BuildContext context) {
  // design-system exception (approved): 14pt sits between bodySmall (13) and
  // bodyMedium (16); chosen so block code reads at roughly the size of
  // surrounding prose without dominating it.
  return context.monospaceOn(const TextStyle(fontSize: 14));
}

/// The syntax colours for the current brightness.
Map<String, TextStyle> codeTheme(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? vs2015Theme : githubTheme;

/// Syntax-highlighted source code, selectable on its own or, when
/// [selectable] is false, as part of an enclosing [SelectionArea].
class CodeView extends StatelessWidget {
  const CodeView({
    super.key,
    required this.code,
    required this.language,
    this.selectable = true,
  });

  final String code;
  final String language;

  /// Whether the code manages its own selection (via `SelectableText`). Pass
  /// `false` inside a `SelectionArea` so the area handles selection; a
  /// self-selecting widget nested in one drops out of the area's selection.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final theme = codeTheme(context);
    final root = theme[_rootKey];
    final style = codeTextStyle(context).copyWith(color: root?.color);
    final span = TextSpan(
      style: style,
      children: highlightSpans(
        code.replaceAll('\t', ' ' * _tabWidth),
        language,
        theme,
      ),
    );
    return ColoredBox(
      color: root?.backgroundColor ?? Colors.transparent,
      // Replaces the ambient style so prose line height and letter spacing
      // do not reach the code.
      child: DefaultTextStyle(
        style: style,
        child: selectable ? SelectableText.rich(span) : Text.rich(span),
      ),
    );
  }
}
