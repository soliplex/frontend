import 'package:soliplex_client/soliplex_client.dart';
import 'package:test/test.dart';

void main() {
  group('decodeMapSafely', () {
    test('returns DecodedEvent with the decoded event and original Map', () {
      final raw = <String, dynamic>{
        'type': 'TEXT_MESSAGE_START',
        'messageId': 'msg-1',
        'role': 'user',
      };

      final outcome = decodeMapSafely(raw);

      expect(outcome, isA<DecodedEvent>());
      final decoded = outcome as DecodedEvent;
      expect(decoded.event, isA<TextMessageStartEvent>());
      expect(
        identical(decoded.rawJson, raw),
        isTrue,
        reason: 'rawJson should be the same Map passed in',
      );
    });

    test('returns DecodeFailed when the decoder throws', () {
      // Unknown event type — the decoder throws on EventType.fromString.
      final raw = <String, dynamic>{'type': 'NOT_A_REAL_EVENT_TYPE'};

      final outcome = decodeMapSafely(raw);

      expect(outcome, isA<DecodeFailed>());
      final failed = outcome as DecodeFailed;
      expect(failed.error, isNotNull);
      expect(failed.rawData, equals(raw));
    });

    test('returns DecodeFailed for missing required fields', () {
      // TEXT_MESSAGE_START requires messageId; omitting it triggers a
      // decoder failure that the wrapper must catch rather than propagate.
      final raw = <String, dynamic>{'type': 'TEXT_MESSAGE_START'};

      final outcome = decodeMapSafely(raw);

      expect(outcome, isA<DecodeFailed>());
    });
  });
}
