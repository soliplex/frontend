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
///
/// Code and JSON longer than [maxHighlightedLength] show as plain text under a
/// notice, with no highlighting and no Tree view, streaming or not. SVG has no
/// limit.
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
    final kind = contentKindOf(language);
    return switch (kind) {
      ContentKind.svg => Semantics(
          label: 'SVG image',
          child: SvgBody(
            content: content,
            fill: fill,
            isStreaming: isStreaming,
            selectable: selectable,
          ),
        ),
      ContentKind.json || ContentKind.code => _codeBlock(kind),
    };
  }

  Widget _codeBlock(ContentKind kind) {
    final isJson = kind == ContentKind.json;
    final label = isJson
        ? 'json'
        : language == 'plaintext'
            ? null
            : language;
    final tooLarge = content.length > maxHighlightedLength;
    return Semantics(
      label: label == null ? 'Code block' : 'Code block in $label',
      child: isJson && !tooLarge
          ? JsonViewer.source(
              content,
              initialView: ContentView.source,
              fill: fill,
              selectable: selectable,
              isStreaming: isStreaming,
            )
          : ContentFrame(
              header: ContentHeader(
                label: label,
                copyText: content,
                copyTooltip: isJson ? 'Copy JSON' : 'Copy code',
              ),
              notice: tooLarge
                  ? const RenderFailureNotice(
                      message: 'Too large to highlight; showing plain text.',
                    )
                  : null,
              body: CodeView(
                code: content,
                language: tooLarge ? 'plaintext' : language,
                selectable: selectable,
              ),
              fill: fill,
            ),
    );
  }
}
