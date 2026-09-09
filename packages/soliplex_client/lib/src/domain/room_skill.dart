import 'package:meta/meta.dart';

/// A skill configured in a room.
@immutable
class RoomSkill {
  /// Creates a room skill.
  const RoomSkill({
    required this.name,
    required this.description,
    this.source,
    this.stateNamespace,
    this.extraParameters = const {},
    this.stateTypeSchema = const {},
  });

  /// Skill name as configured in the backend.
  final String name;

  /// Human-readable description of what the skill does.
  final String description;

  /// Where the skill was loaded from (e.g., 'filesystem', 'entrypoint').
  final String? source;

  /// AG-UI state namespace for this skill.
  final String? stateNamespace;

  /// Skill-specific configuration the backend passes through verbatim.
  final Map<String, dynamic> extraParameters;

  /// JSON schema describing the skill's AG-UI state type. Empty for a skill
  /// that carries no AG-UI state.
  final Map<String, dynamic> stateTypeSchema;

  @override
  String toString() => 'RoomSkill(name: $name, source: $source)';
}
