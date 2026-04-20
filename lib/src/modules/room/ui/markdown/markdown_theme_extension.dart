import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class MarkdownThemeExtension extends ThemeExtension<MarkdownThemeExtension> {
  const MarkdownThemeExtension({
    this.h1,
    this.h2,
    this.h3,
    this.body,
    this.code,
    this.link,
    this.codeBlockDecoration,
    this.blockquoteDecoration,
  });

  final TextStyle? h1;
  final TextStyle? h2;
  final TextStyle? h3;
  final TextStyle? body;
  final TextStyle? code;
  final TextStyle? link;
  final Decoration? codeBlockDecoration;
  final Decoration? blockquoteDecoration;

  MarkdownStyleSheet toMarkdownStyleSheet({TextStyle? codeFontStyle}) {
    final mergedCode = codeFontStyle?.merge(code) ?? code;
    return MarkdownStyleSheet(
      h1: h1,
      h2: h2,
      h3: h3,
      p: body,
      code: mergedCode,
      a: link,
      codeblockDecoration: codeBlockDecoration,
      blockquoteDecoration: blockquoteDecoration,
    );
  }

  @override
  MarkdownThemeExtension copyWith({
    TextStyle? h1,
    TextStyle? h2,
    TextStyle? h3,
    TextStyle? body,
    TextStyle? code,
    TextStyle? link,
    Decoration? codeBlockDecoration,
    Decoration? blockquoteDecoration,
  }) {
    return MarkdownThemeExtension(
      h1: h1 ?? this.h1,
      h2: h2 ?? this.h2,
      h3: h3 ?? this.h3,
      body: body ?? this.body,
      code: code ?? this.code,
      link: link ?? this.link,
      codeBlockDecoration: codeBlockDecoration ?? this.codeBlockDecoration,
      blockquoteDecoration: blockquoteDecoration ?? this.blockquoteDecoration,
    );
  }

  @override
  MarkdownThemeExtension lerp(
    covariant MarkdownThemeExtension? other,
    double t,
  ) {
    if (other == null) return this;
    return MarkdownThemeExtension(
      h1: TextStyle.lerp(h1, other.h1, t),
      h2: TextStyle.lerp(h2, other.h2, t),
      h3: TextStyle.lerp(h3, other.h3, t),
      body: TextStyle.lerp(body, other.body, t),
      code: TextStyle.lerp(code, other.code, t),
      link: TextStyle.lerp(link, other.link, t),
      codeBlockDecoration: Decoration.lerp(
        codeBlockDecoration,
        other.codeBlockDecoration,
        t,
      ),
      blockquoteDecoration: Decoration.lerp(
        blockquoteDecoration,
        other.blockquoteDecoration,
        t,
      ),
    );
  }
}
