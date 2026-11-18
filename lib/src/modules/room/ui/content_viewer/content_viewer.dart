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
    final tooLarge = content.length > maxHighlightedLength;
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
          label: 'JSON',
          child: tooLarge
              ? _codeFrame(
                  label: 'json',
                  copyTooltip: 'Copy JSON',
                  highlightAs: null,
                )
              : JsonViewer.source(
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
          child: _codeFrame(
            label: language == 'plaintext' ? null : language,
            copyTooltip: 'Copy code',
            highlightAs: tooLarge ? null : language,
          ),
        ),
    };
  }

  /// The header, the code body and, when [highlightAs] is null, the notice
  /// that it is shown as plain text.
  Widget _codeFrame({
    required String? label,
    required String copyTooltip,
    required String? highlightAs,
  }) {
    return ContentFrame(
      header: ContentHeader(
        label: label,
        copyText: content,
        copyTooltip: copyTooltip,
      ),
      notice: highlightAs == null
          ? const ContentInfoNotice(
              message: 'Too large to highlight; showing plain text.',
            )
          : null,
      body: CodeView(
        code: content,
        language: highlightAs ?? 'plaintext',
        selectable: selectable,
      ),
      fill: fill,
    );
  }
}
