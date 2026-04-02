import 'package:meta/meta.dart';

/// A skill configured in a room.
@immutable
class RoomSkill {
  /// Creates a room skill.
  const RoomSkill({
    required this.name,
    required this.description,
    this.source,
    this.license,
    this.compatibility,
    this.allowedTools,
    this.stateNamespace,
    this.metadata = const {},
    this.stateTypeSchema,
  });

  /// Skill name as configured in the backend.
  final String name;

  /// Human-readable description of what the skill does.
  final String description;

  /// Where the skill was loaded from (e.g., 'filesystem', 'entrypoint').
  final String? source;

  /// License of the skill (e.g., 'MIT').
  final String? license;

  /// Version compatibility string.
  final String? compatibility;

  /// Tools this skill is allowed to use.
  final List<String>? allowedTools;

  /// AG-UI state namespace for this skill.
  final String? stateNamespace;

  /// Arbitrary metadata key-value pairs.
  final Map<String, dynamic> metadata;

  /// JSON schema describing the skill's AG-UI state type.
  final Map<String, dynamic>? stateTypeSchema;

  @override
  String toString() => 'RoomSkill(name: $name, source: $source)';
}
