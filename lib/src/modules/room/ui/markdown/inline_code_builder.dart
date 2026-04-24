import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../../../../../soliplex_frontend.dart';

class InlineCodeBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          colorScheme.onSurface.withAlpha(30),
          colorScheme.surface,
        ),
      ),
      child: Text(
        element.textContent,
        style: preferredStyle?.copyWith(
          backgroundColor: Colors.transparent,
        ),
      ),
    );
  }
}
