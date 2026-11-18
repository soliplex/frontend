import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

import '../content_viewer/content_kind.dart';
import '../content_viewer/content_viewer.dart';

/// Whether the message the markdown below renders is still streaming in.
///
/// An inherited widget rather than a [CodeBlockBuilder] argument because
/// `MarkdownBody` caches the blocks it built and rebuilds them only when its
/// text or style sheet changes, and a message can stop streaming with its
/// text unchanged.
class FenceStreaming extends InheritedWidget {
  const FenceStreaming({
    super.key,
    required this.isStreaming,
    required super.child,
  });

  final bool isStreaming;

  /// The nearest [isStreaming], or false when no [FenceStreaming] is above:
  /// markdown without one is complete.
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<FenceStreaming>()
          ?.isStreaming ??
      false;

  @override
  bool updateShouldNotify(FenceStreaming oldWidget) =>
      isStreaming != oldWidget.isStreaming;
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  CodeBlockBuilder({required this.selectable});

  /// Whether each block manages its own selection; `false` inside a
  /// `SelectionArea`.
  final bool selectable;

  @override
  Widget? visitElementAfter(
    md.Element element,
    TextStyle? preferredStyle,
  ) {
    return _Fence(
      language: _languageFrom(element),
      content: element.textContent,
      selectable: selectable,
    );
  }

  static String _languageFrom(md.Element pre) {
    final children = pre.children;
    if (children != null) {
      for (final child in children) {
        if (child is md.Element && child.tag == 'code') {
          final className = child.attributes['class'];
          if (className != null && className.startsWith('language-')) {
            return fenceLanguage(className.replaceFirst('language-', ''));
          }
        }
      }
    }
    return 'plaintext';
  }
}

class _Fence extends StatelessWidget {
  const _Fence({
    required this.language,
    required this.content,
    required this.selectable,
  });

  final String language;
  final String content;
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    return ContentViewer(
      language: language,
      content: content,
      fill: false,
      isStreaming: FenceStreaming.of(context),
      selectable: selectable,
    );
  }
}
