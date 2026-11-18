import 'package:flutter/material.dart';

import '../../../../shared/content/code_view.dart';
import '../../../../shared/content/content_frame.dart';
import '../../../../shared/content/json_viewer.dart';
import 'content_kind.dart';
import 'svg_body.dart';

/// [content] under the shared header, rendered by the viewer for its
/// [language].
///
/// Inline ([fill] false), the viewer is as tall as its content, an SVG picture
/// capped at 400; filling, it takes the height it is given, which must be
/// bounded. [isStreaming] says the content may still be
/// incomplete, so a failed rendering shows no notice yet. Pass [selectable]
/// false inside a `SelectionArea`.
class ContentViewer extends StatelessWidget {
  const ContentViewer({
    super.key,
    required this.language,
    required this.content,
    required this.fill,
    this.isStreaming = false,
    this.selectable = true,
  });

  final String language;
  final String content;
  final bool fill;
  final bool isStreaming;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return switch (contentKindOf(language)) {
      ContentKind.svg => Semantics(
          label: 'SVG image',
          child: SvgBody(
            content: content,
            fill: fill,
            isStreaming: isStreaming,
            selectable: selectable,
          ),
        ),
      ContentKind.json => Semantics(
          label: 'Code block in json',
          child: JsonViewer.source(
            content,
            initialView: ContentView.source,
            fill: fill,
            selectable: selectable,
            isStreaming: isStreaming,
          ),
        ),
      ContentKind.code => Semantics(
          label: language == 'plaintext'
              ? 'Code block'
              : 'Code block in $language',
          child: ContentFrame(
            header: ContentHeader(
              label: language == 'plaintext' ? null : language,
              copyText: content,
              copyTooltip: 'Copy code',
            ),
            body: CodeView(
              code: content,
              language: language,
              selectable: selectable,
            ),
            fill: fill,
          ),
        ),
    };
  }
}
