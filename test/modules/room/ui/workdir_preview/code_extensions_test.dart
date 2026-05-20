import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/code_extensions.dart';

void main() {
  group('languageForExtension', () {
    test('maps common extensions to highlight language ids', () {
      expect(languageForExtension('dart'), 'dart');
      expect(languageForExtension('py'), 'python');
      expect(languageForExtension('js'), 'javascript');
      expect(languageForExtension('ts'), 'typescript');
      expect(languageForExtension('rs'), 'rust');
      expect(languageForExtension('yaml'), 'yaml');
      expect(languageForExtension('yml'), 'yaml');
      expect(languageForExtension('sh'), 'bash');
    });

    test('is case-insensitive on the extension', () {
      expect(languageForExtension('PY'), 'python');
      expect(languageForExtension('Dart'), 'dart');
    });

    test('falls back to plaintext for unknown extensions', () {
      expect(languageForExtension('mystery'), 'plaintext');
      expect(languageForExtension(''), 'plaintext');
    });
  });
}
