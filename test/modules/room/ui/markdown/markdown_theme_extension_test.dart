import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/markdown/markdown_theme_extension.dart';

void main() {
  test('toMarkdownStyleSheet applies heading and body styles', () {
    final ext = MarkdownThemeExtension(
      h1: const TextStyle(fontSize: 24),
      body: const TextStyle(fontSize: 16),
      codeBlockDecoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.zero,
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

  test('copyWith overrides specified fields', () {
    final original = MarkdownThemeExtension(
      h1: const TextStyle(fontSize: 24),
      h2: const TextStyle(fontSize: 20),
    );
    final copied = original.copyWith(h1: const TextStyle(fontSize: 30));
    expect(copied.h1?.fontSize, 30);
    expect(copied.h2?.fontSize, 20);
  });
}
