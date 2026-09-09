import 'package:meta/meta.dart';

/// Agent configuration for a room.
///
/// The backend sends one of three shapes, told apart by which fields
/// the payload carries rather than by a discriminator field:
/// - [DefaultRoomAgent]: Standard LLM agent with model and prompt config
/// - [FactoryRoomAgent]: Custom agent created by a Python factory function
/// - [OtherRoomAgent]: Unknown agent kind for forward compatibility
@immutable
sealed class RoomAgent {
  const RoomAgent({required this.id, this.aguiFeatureNames = const []});

  /// Unique identifier for the agent.
  ///
  /// Parsed but deliberately not rendered: the backend derives it as
  /// `room-{room_id}` (`config/rooms.py`), so it restates the room id the
  /// screen already shows. It is kept because for an agent kind this client
  /// does not model, its absence is the only thing `roomAgentFromJson` can
  /// reject the block on.
  final String id;

  /// AG-UI feature names enabled for this agent.
  final List<String> aguiFeatureNames;
}

/// Standard LLM agent with model configuration.
@immutable
class DefaultRoomAgent extends RoomAgent {
  /// Creates a default room agent.
  const DefaultRoomAgent({
    required super.id,
    required this.providerType,
    this.retries,
    this.modelName,
    this.systemPrompt,
    super.aguiFeatureNames,
  });

  /// LLM model name (e.g., 'gpt-4o', 'claude-3-opus').
  final String? modelName;

  /// Number of retry attempts for LLM calls, or null when the backend sent
  /// none — the field is required on the wire, so its absence is drift.
  final int? retries;

  /// The system prompt text, if configured.
  final String? systemPrompt;

  /// LLM provider type (e.g., 'openai', 'ollama').
  final String providerType;

  @override
  String toString() => 'DefaultRoomAgent(id: $id, model: $modelName)';
}

/// Agent created by a Python factory function.
@immutable
class FactoryRoomAgent extends RoomAgent {
  /// Creates a factory room agent.
  const FactoryRoomAgent({
    required super.id,
    required this.factoryName,
    this.extraConfig = const {},
    super.aguiFeatureNames,
  });

  /// Dotted Python import path for the factory function.
  final String factoryName;

  /// Additional configuration passed to the factory.
  final Map<String, dynamic> extraConfig;

  @override
  String toString() => 'FactoryRoomAgent(id: $id, factory: $factoryName)';
}

/// Unknown agent kind for forward compatibility.
@immutable
class OtherRoomAgent extends RoomAgent {
  /// Creates an agent with an unknown kind.
  const OtherRoomAgent({
    required super.id,
    required this.kind,
    super.aguiFeatureNames,
  });

  /// The agent kind string from the backend.
  final String kind;

  @override
  String toString() => 'OtherRoomAgent(id: $id, kind: $kind)';
}
