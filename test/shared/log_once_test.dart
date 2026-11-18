import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/log_once.dart';

void main() {
  // The set is process-wide, so each test uses keys no other test uses.
  test('isFirstOccurrence is true once per key', () {
    expect(isFirstOccurrence('log-once-repeat'), isTrue);
    expect(isFirstOccurrence('log-once-repeat'), isFalse);
  });

  test('distinct keys are each first', () {
    expect(isFirstOccurrence('log-once-distinct-a'), isTrue);
    expect(isFirstOccurrence('log-once-distinct-b'), isTrue);
  });
}
