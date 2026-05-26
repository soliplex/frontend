import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() {
  group('monospaceFontFamily', () {
    test('Apple platforms use SF Mono with Menlo fallback', () {
      for (final p in [TargetPlatform.iOS, TargetPlatform.macOS]) {
        final mono = monospaceFontFamily(p);
        expect(mono.family, 'SF Mono');
        expect(mono.fallback, const ['Menlo', 'monospace']);
      }
    });

    test('non-Apple platforms use Roboto Mono', () {
      for (final p in [
        TargetPlatform.android,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        final mono = monospaceFontFamily(p);
        expect(mono.family, 'Roboto Mono');
        expect(mono.fallback, const ['monospace']);
      }
    });
  });
}
