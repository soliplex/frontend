import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';

import 'code_block_builder.dart';
import 'data_uri_image.dart';
import 'inline_code_builder.dart';
import 'markdown_renderer.dart';
import 'markdown_theme_extension.dart';

final _brTag = RegExp(r'<br\s*/?>');

String sanitizeMarkdown(String markdown) => markdown.replaceAll(_brTag, '\n');

String monospaceFont(TargetPlatform platform) {
  final isApple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  return isApple ? 'SF Mono' : 'Roboto Mono';
}

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
    final monoStyle = TextStyle(
      fontFamily: monospaceFont(Theme.of(context).platform),
      fontFamilyFallback: const ['monospace'],
    );

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
      imageBuilder: _buildImage,
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

Widget _buildImage(Uri uri, String? title, String? alt) {
  if (uri.scheme == 'data') {
    final decoded = tryDecodeImageDataUri(uri.toString());
    if (decoded == null) return BrokenImagePlaceholder(alt: alt);
    return Image.memory(
      decoded.bytes,
      errorBuilder: (_, __, ___) => BrokenImagePlaceholder(alt: alt),
    );
  }
  if (uri.scheme == 'http' || uri.scheme == 'https') {
    return Image.network(
      uri.toString(),
      errorBuilder: (_, __, ___) => BrokenImagePlaceholder(alt: alt),
    );
  }
  return BrokenImagePlaceholder(alt: alt);
}
