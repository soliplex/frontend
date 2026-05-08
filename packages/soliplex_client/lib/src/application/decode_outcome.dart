import 'package:ag_ui/ag_ui.dart';
import 'package:meta/meta.dart';

/// Result of decoding a single AG-UI event payload.
///
/// Used at both the live SSE boundary (`AgUiStreamClient`) and the replay
/// boundary (`SoliplexApi._replayEventsToHistory`) so a malformed or
/// unrecognized event surfaces as a tile in the conversation rather than
/// aborting the run.
@immutable
sealed class DecodeOutcome {
  const DecodeOutcome();
}

/// A successfully decoded event paired with its original JSON form.
///
/// The original JSON is retained so a downstream throw inside `processEvent`
/// can attach it to a `DroppedEventMessage` without reflection.
@immutable
class DecodedEvent extends DecodeOutcome {
  /// Creates a decoded-event outcome.
  const DecodedEvent(this.event, this.rawJson);

  /// The decoded AG-UI event.
  final BaseEvent event;

  /// The original JSON object the event was decoded from.
  final Map<String, dynamic> rawJson;
}

/// A failed decode capturing the original payload for diagnostics.
///
/// [rawData] may be a `Map` (decoder failure on a single event), a `String`
/// (top-level JSON parse failure), or a non-Map JSON value (list/scalar).
@immutable
class DecodeFailed extends DecodeOutcome {
  /// Creates a decode-failure outcome.
  const DecodeFailed(this.error, this.rawData);

  /// The error thrown by the decoder or JSON parser.
  final Object error;

  /// The raw payload that failed to decode.
  final Object rawData;
}

/// Decodes a single JSON object into a [DecodeOutcome].
///
/// Catches every throw from [EventDecoder.decodeJson] (unknown event types,
/// missing required fields, type mismatches) and returns a [DecodeFailed]
/// envelope so callers can render a tile at the failure position.
DecodeOutcome decodeMapSafely(Map<String, dynamic> map) {
  try {
    return DecodedEvent(const EventDecoder().decodeJson(map), map);
  } on Object catch (e) {
    return DecodeFailed(e, map);
  }
}
