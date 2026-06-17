import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:soliplex_design/soliplex_design.dart';

import 'launch_markdown_link.dart';
import 'markdown_renderer.dart';
import 'markdown_style_sheet.dart';
import 'sanitize_markdown.dart';

/// Renders trusted, author-provided prose markdown — paragraphs, lists,
/// emphasis, and external links — for static copy surfaces such as the consent
/// notice. Deliberately excludes the chat renderer's LaTeX, code, and image
/// builders; `onImageTap` (inherited from [MarkdownRenderer]) is unused because
/// prose renders no images.
class ProseMarkdown extends MarkdownRenderer {
  const ProseMarkdown({
    required super.data,
    this.textStyle,
    super.onLinkTap,
    super.key,
  });

  /// Overrides the paragraph (`p`) style — e.g. to dim the body. When null the
  /// shared markdown theme's body style applies.
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final markdownTheme = Theme.of(context).extension<MarkdownThemeExtension>();
    final base = markdownTheme?.toMarkdownStyleSheet() ??
        MarkdownStyleSheet.fromTheme(Theme.of(context));
    final styleSheet = textStyle == null ? base : base.copyWith(p: textStyle);

    return MarkdownBody(
      data: sanitizeMarkdown(data),
      selectable: false,
      styleSheet: styleSheet,
      extensionSet: md.ExtensionSet.gitHubFlavored,
      onTapLink: (_, href, title) {
        if (href == null) return;
        final handleTap = onLinkTap;
        if (handleTap != null) {
          handleTap(href, title);
        } else {
          launchMarkdownLink(href);
        }
      },
    );
  }
}
