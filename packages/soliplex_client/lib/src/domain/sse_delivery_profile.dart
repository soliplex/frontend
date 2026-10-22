import 'package:meta/meta.dart';

/// A named way the installation can deliver a run's SSE stream, which a run
/// may ask for by [name].
@immutable
class SseDeliveryProfile {
  /// Creates an SSE delivery profile.
  const SseDeliveryProfile({required this.name, required this.strategy});

  /// The name a run sends to ask for this profile.
  final String name;

  /// How the profile groups streamed deltas: `message` holds each message
  /// until it ends, `bounded` sends merged deltas as they accumulate.
  final String strategy;
}
