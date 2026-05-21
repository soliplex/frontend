import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_files_section.dart';

void main() {
  group('fitFilenameForWidth', () {
    const style = TextStyle(fontSize: 12);

    test('returns the input unchanged when it fits', () {
      expect(fitFilenameForWidth('short.dart', style, 10000), 'short.dart');
    });

    test('preserves the extension when truncating a long basename', () {
      final result = fitFilenameForWidth(
        'a-very-long-basename-that-needs-truncation.dart',
        style,
        80,
      );
      expect(result.endsWith('.dart'), isTrue,
          reason: 'extension must survive truncation: $result');
      expect(result, contains('…'));
    });

    test('falls back to whole-name ellipsis for leading-dot files', () {
      // .bashrc has no useful prefix-extension split — the extension
      // *is* the whole name. Falls back to plain end-ellipsis.
      final result = fitFilenameForWidth('.bashrc', style, 20);
      expect(result.endsWith('.bashrc'), isFalse);
      expect(result, contains('…'));
    });

    test('falls back to whole-name ellipsis when extension is too long', () {
      // The "useful extension" rule caps at 8 chars; 10-char extensions
      // get the plain end-ellipsis treatment.
      final result = fitFilenameForWidth(
        'some-file-name.extensionTen',
        style,
        60,
      );
      expect(result, contains('…'));
    });
  });
}
