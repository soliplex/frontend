import 'package:meta/meta.dart';

import 'package:soliplex_client/src/domain/mcp_client_toolset.dart';
import 'package:soliplex_client/src/domain/room_agent.dart';
import 'package:soliplex_client/src/domain/room_skill.dart';
import 'package:soliplex_client/src/domain/room_tool.dart';

/// Represents a room from the backend.
@immutable
class Room {
  /// Creates a room.
  const Room({
    required this.id,
    required this.name,
    this.description = '',
    this.metadata = const {},
    this.quizzes = const {},
    this.suggestions = const [],
    this.welcomeMessage = '',
    this.enableAttachments = false,
    this.allowMcp = false,
    this.agent,
    this.skills = const {},
    this.tools = const {},
    this.mcpClientToolsets = const {},
    this.toolDefinitions = const [],
    this.aguiFeatureNames = const [],
  });

  /// Unique identifier for the room.
  final String id;

  /// Display name of the room.
  final String name;

  /// Description of the room (empty string if not provided).
  final String description;

  /// Metadata for the room (empty map if not provided).
  final Map<String, dynamic> metadata;

  /// Quizzes available in this room, keyed by quiz ID with title
  /// as value.
  final Map<String, String> quizzes;

  /// Suggested prompts to show when starting a new thread.
  final List<String> suggestions;

  /// Welcome message shown when entering the room.
  final String welcomeMessage;

  /// Whether file attachments are enabled for this room.
  final bool enableAttachments;

  /// Whether MCP server access is allowed for this room.
  final bool allowMcp;

  /// Agent configuration for this room.
  final RoomAgent? agent;

  /// Skills configured in this room, keyed by skill name.
  final Map<String, RoomSkill> skills;

  /// Tools configured in this room, keyed by tool name.
  final Map<String, RoomTool> tools;

  /// MCP client toolsets configured in this room.
  final Map<String, McpClientToolset> mcpClientToolsets;

  /// Raw tool definitions from the backend (validated dicts).
  ///
  /// Stored as raw maps to keep the Room model backend-shape-agnostic.
  /// Convert to ag_ui Tool objects at the provider layer.
  final List<Map<String, dynamic>> toolDefinitions;

  /// AG-UI feature names enabled for this room.
  final List<String> aguiFeatureNames;

  /// Quiz IDs available in this room.
  List<String> get quizIds => quizzes.keys.toList();

  /// Whether the room has a description.
  bool get hasDescription => description.isNotEmpty;

  /// Whether the room has any quizzes.
  bool get hasQuizzes => quizzes.isNotEmpty;

  /// Whether the room has any suggestions.
  bool get hasSuggestions => suggestions.isNotEmpty;

  /// Whether the room has a welcome message.
  bool get hasWelcomeMessage => welcomeMessage.isNotEmpty;

  /// Whether the room has any tool definitions.
  bool get hasToolDefinitions => toolDefinitions.isNotEmpty;

  /// Whether the room has any AG-UI feature names.
  bool get hasAguiFeatures => aguiFeatureNames.isNotEmpty;

  /// Creates a copy of this room with the given fields replaced.
  Room copyWith({
    String? id,
    String? name,
    String? description,
    Map<String, dynamic>? metadata,
    Map<String, String>? quizzes,
    List<String>? suggestions,
    String? welcomeMessage,
    bool? enableAttachments,
    bool? allowMcp,
    RoomAgent? agent,
    Map<String, RoomSkill>? skills,
    Map<String, RoomTool>? tools,
    Map<String, McpClientToolset>? mcpClientToolsets,
    List<Map<String, dynamic>>? toolDefinitions,
    List<String>? aguiFeatureNames,
  }) {
    return Room(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      metadata: metadata ?? this.metadata,
      quizzes: quizzes ?? this.quizzes,
      suggestions: suggestions ?? this.suggestions,
      welcomeMessage: welcomeMessage ?? this.welcomeMessage,
      enableAttachments: enableAttachments ?? this.enableAttachments,
      allowMcp: allowMcp ?? this.allowMcp,
      agent: agent ?? this.agent,
      skills: skills ?? this.skills,
      tools: tools ?? this.tools,
      mcpClientToolsets: mcpClientToolsets ?? this.mcpClientToolsets,
      toolDefinitions: toolDefinitions ?? this.toolDefinitions,
      aguiFeatureNames: aguiFeatureNames ?? this.aguiFeatureNames,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Room && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Room(id: $id, name: $name)';
}
