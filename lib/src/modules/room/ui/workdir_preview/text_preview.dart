import 'package:flutter/material.dart';

import '../../../../design/design.dart';
import '../markdown/flutter_markdown_plus_renderer.dart';

/// Renders [content] through the shared markdown renderer. Used for
/// both `.md` files and plain-text files — plain text routes through
/// markdown so any embedded markdown syntax in the file renders
/// alongside the prose.
class TextPreview extends StatelessWidget {
  const TextPreview({super.key, required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      child: FlutterMarkdownPlusRenderer(data: content),
    );
  }
}
