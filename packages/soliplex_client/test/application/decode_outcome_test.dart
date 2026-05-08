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
      // The stack trace is the source of every drop-tile breadcrumb
      // downstream: orchestrator, replay, and the logger calls all
      // forward `failed.stackTrace`. If `decodeMapSafely` stops
      // capturing it, every Sentry breadcrumb on this path loses its
      // throw site.
      expect(failed.stackTrace, isNotNull);
    });
  });

  test('EventDecoder rejects unknown event types', () {
    // Build-time guard against a future ag_ui release that introduces a
    // fallback variant (e.g., decoding unknown types into `RawEvent` /
    // `CustomEvent`). The drop-tile carrier relies on the throw — if
    // ag_ui starts succeeding on unknown types instead, our boundary
    // silently flips from "drop tile" to "pass-through unknown event"
    // and `decodeMapSafely` stops emitting `DecodeFailed` for them.
    expect(
      () => const EventDecoder().decodeJson({'type': 'NOT_A_REAL_EVENT_TYPE'}),
      throwsA(isNotNull),
    );
  });
}
