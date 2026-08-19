import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/shared/type_to_focus.dart';

void main() {
  group('isTypedText', () {
    test('accepts printable characters, including space', () {
      expect(isTypedText('h'), isTrue);
      expect(isTypedText(' '), isTrue);
      expect(isTypedText('\u00e9'), isTrue);
    });

    test('rejects the control codes macOS and Linux report for control keys',
        () {
      // The Windows engine filters these; macOS and Linux pass them through, so
      // Enter, Tab, Escape and Delete would otherwise be typed into the field.
      expect(isTypedText('\r'), isFalse, reason: 'Enter');
      expect(isTypedText('\t'), isFalse, reason: 'Tab');
      expect(isTypedText('\u001b'), isFalse, reason: 'Escape');
      expect(isTypedText('\u007f'), isFalse, reason: 'Delete');
    });

    test('rejects absent or empty text', () {
      expect(isTypedText(null), isFalse);
      expect(isTypedText(''), isFalse);
    });
  });
}
