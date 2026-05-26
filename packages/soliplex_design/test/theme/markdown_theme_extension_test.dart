import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_design/soliplex_design.dart';

void main() {
  test('copyWith overrides specified fields', () {
    const original = MarkdownThemeExtension(
      h1: TextStyle(fontSize: 24),
      h2: TextStyle(fontSize: 20),
    );
    final copied = original.copyWith(h1: const TextStyle(fontSize: 30));
    expect(copied.h1?.fontSize, 30);
    expect(copied.h2?.fontSize, 20);
  });

  test('lerp at t=0 returns this when other is null', () {
    const ext = MarkdownThemeExtension(h1: TextStyle(fontSize: 24));
    expect(ext.lerp(null, 0.5), same(ext));
  });

  test('lerp blends text styles between two extensions', () {
    const a = MarkdownThemeExtension(h1: TextStyle(fontSize: 20));
    const b = MarkdownThemeExtension(h1: TextStyle(fontSize: 40));
    final mid = a.lerp(b, 0.5);
    expect(mid.h1?.fontSize, 30);
  });
}
