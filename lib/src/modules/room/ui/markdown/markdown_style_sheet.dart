import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:soliplex_design/soliplex_design.dart';

extension MarkdownThemeExtensionStyleSheet on MarkdownThemeExtension {
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
}
