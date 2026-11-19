import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/log_once.dart';

void main() {
  tearDown(forgetOccurrences);

  test('isFirstOccurrence is true once per key', () {
    expect(isFirstOccurrence('repeat'), isTrue);
    expect(isFirstOccurrence('repeat'), isFalse);
  });

  test('distinct keys are each first', () {
    expect(isFirstOccurrence('distinct-a'), isTrue);
    expect(isFirstOccurrence('distinct-b'), isTrue);
  });

  test('forgetOccurrences makes a seen key first again', () {
    expect(isFirstOccurrence('forgotten'), isTrue);

    forgetOccurrences();

    expect(isFirstOccurrence('forgotten'), isTrue);
  });
}
