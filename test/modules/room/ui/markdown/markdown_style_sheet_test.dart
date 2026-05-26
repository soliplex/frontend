import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/markdown/markdown_style_sheet.dart';

void main() {
  test('toMarkdownStyleSheet applies heading and body styles', () {
    final ext = MarkdownThemeExtension(
      h1: const TextStyle(fontSize: 24),
      body: const TextStyle(fontSize: 16),
      codeBlockDecoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(8),
      ),
    );

    final sheet = ext.toMarkdownStyleSheet();
    expect(sheet.h1?.fontSize, 24);
    expect(sheet.p?.fontSize, 16);
    expect(sheet.codeblockDecoration, isNotNull);
  });

  test('toMarkdownStyleSheet merges codeFontStyle with code', () {
    final ext = MarkdownThemeExtension(
      code: const TextStyle(backgroundColor: Colors.black12),
    );

    final sheet = ext.toMarkdownStyleSheet(
      codeFontStyle: const TextStyle(fontFamily: 'monospace', fontSize: 14),
    );
    expect(sheet.code?.fontFamily, 'monospace');
    expect(sheet.code?.fontSize, 14);
    expect(sheet.code?.backgroundColor, Colors.black12);
  });
}
