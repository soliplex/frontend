import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';

import '../../../../design/theme/theme_extensions.dart';
import 'code_block_builder.dart';
import 'inline_code_builder.dart';
import 'markdown_renderer.dart';
import 'markdown_theme_extension.dart';

final _brTag = RegExp(r'<br\s*/?>');

String sanitizeMarkdown(String markdown) => markdown.replaceAll(_brTag, '\n');

class FlutterMarkdownPlusRenderer extends MarkdownRenderer {
  const FlutterMarkdownPlusRenderer({
    required super.data,
    super.onLinkTap,
    super.onImageTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final markdownTheme = Theme.of(context).extension<MarkdownThemeExtension>();
    final monoStyle = SoliplexTheme.codeStyle(context);

    return MarkdownBody(
      data: sanitizeMarkdown(data),
      selectable: true,
      styleSheet: markdownTheme?.toMarkdownStyleSheet(
        codeFontStyle: monoStyle,
      ),
      blockSyntaxes: [LatexBlockSyntax()],
      inlineSyntaxes: [LatexInlineSyntax()],
      onTapLink: onLinkTap == null
          ? null
          : (_, href, title) {
              if (href != null) onLinkTap!(href, title);
            },
      builders: {
        'code': InlineCodeBuilder(),
        'pre': CodeBlockBuilder(
          preferredStyle: monoStyle.copyWith(fontSize: 14),
        ),
        'latex': LatexElementBuilder(),
      },
    );
  }
}
