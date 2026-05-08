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
/// The original JSON is retained so a `processEvent` throw can attach
/// the raw payload to its drop tile.
@immutable
class DecodedEvent extends DecodeOutcome {
  /// Pairs the decoded AG-UI [event] with the original [rawJson] it was
  /// decoded from.
  const DecodedEvent(this.event, this.rawJson);

  /// The decoded AG-UI event.
  final BaseEvent event;

  /// The original JSON object the event was decoded from.
  final Map<String, dynamic> rawJson;
}

/// A failed decode capturing the original payload for diagnostics.
///
/// [rawData] is shape-polymorphic: a `Map` (decoder failure on a single
/// event), a `String` (top-level JSON parse failure), a non-Map JSON
/// value (list/scalar), or `null` when the payload itself was the JSON
/// `null` literal. The downstream drop-tile widget renders all four.
@immutable
class DecodeFailed extends DecodeOutcome {
  /// Captures the [error] thrown by the decoder, the [rawData] that
  /// failed to decode, and the [stackTrace] at the throw site (when
  /// available) for breadcrumbs.
  const DecodeFailed(this.error, this.rawData, [this.stackTrace]);

  /// The error thrown by the decoder or JSON parser.
  final Object error;

  /// The raw payload that failed to decode.
  final Object? rawData;

  /// Stack trace from the throw site, when available. The drop-tile
  /// minter forwards this to `Logger.error` so Sentry-grade breadcrumbs
  /// pinpoint the originating call.
  final StackTrace? stackTrace;
}

/// Decodes a single JSON object into a [DecodeOutcome]. Captures the
/// stack trace alongside the error so the drop-tile log carries a
/// breadcrumb back to the throwing decoder arm.
DecodeOutcome decodeMapSafely(Map<String, dynamic> map) {
  try {
    return DecodedEvent(const EventDecoder().decodeJson(map), map);
  } on Object catch (e, st) {
    return DecodeFailed(e, map, st);
  }
}

/// Wraps a synthesized AG-UI event for providers that build events
/// in-process (e.g., `ChatFnLlmProvider`, `StreamingLlmProvider`).
/// Their events have no source JSON, so `rawJson` is `const {}`; if
/// `processEvent` ever throws on one, the resulting drop tile carries
/// an empty payload.
DecodedEvent synthesizedDecoded(BaseEvent event) =>
    DecodedEvent(event, const {});
