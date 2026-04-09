import 'dart:developer' as developer;

import 'package:soliplex_client/src/domain/backend_version_info.dart';
import 'package:soliplex_client/src/domain/mcp_client_toolset.dart';
import 'package:soliplex_client/src/domain/quiz.dart';
import 'package:soliplex_client/src/domain/rag_document.dart';
import 'package:soliplex_client/src/domain/room.dart';
import 'package:soliplex_client/src/domain/room_agent.dart';
import 'package:soliplex_client/src/domain/room_skill.dart';
import 'package:soliplex_client/src/domain/room_tool.dart';
import 'package:soliplex_client/src/domain/run_info.dart';
import 'package:soliplex_client/src/domain/thread_info.dart';

// ============================================================
// Timestamp helpers
// ============================================================

/// Parses a UTC timestamp from the backend.
///
/// Backend sends ISO 8601 timestamps without 'Z' suffix. This normalizes
/// the format and ensures UTC parsing.
///
/// Throws [FormatException] if [raw] is malformed.
DateTime parseTimestamp(String raw) {
  final normalized = raw.endsWith('Z') ? raw : '${raw}Z';
  return DateTime.parse(normalized).toUtc();
}

/// Formats a [DateTime] for the backend.
///
/// Outputs ISO 8601 without 'Z' suffix to match backend format.
String formatTimestamp(DateTime dt) {
  final iso = dt.toUtc().toIso8601String();
  return iso.endsWith('Z') ? iso.substring(0, iso.length - 1) : iso;
}

// ============================================================
// BackendVersionInfo mappers
// ============================================================

/// Creates a [BackendVersionInfo] from JSON.
///
/// Extracts soliplex version and flattens all package versions into a map.
/// Returns 'Unknown' for soliplexVersion if not present.
BackendVersionInfo backendVersionInfoFromJson(Map<String, dynamic> json) {
  final soliplexData = json['soliplex'] as Map<String, dynamic>?;
  final soliplexVersion = soliplexData?['version'] as String? ?? 'Unknown';

  final packageVersions = <String, String>{};
  for (final entry in json.entries) {
    final value = entry.value;
    if (value is Map<String, dynamic>) {
      final version = value['version'];
      if (version is String) {
        packageVersions[entry.key] = version;
      }
    }
  }

  return BackendVersionInfo(
    soliplexVersion: soliplexVersion,
    packageVersions: packageVersions,
  );
}

// ============================================================
// Room mappers
// ============================================================

/// Creates a [RoomAgent] from JSON.
///
/// Discriminates by 'kind' field: 'default', 'factory', or other.
RoomAgent roomAgentFromJson(Map<String, dynamic> json) {
  final kind = json['kind'] as String? ?? '';
  final id = _requireString(json, 'id', 'agent');
  final aguiFeatureNames = _parseStringList(
    json['agui_feature_names'] as List<dynamic>?,
  );

  // Backend omits kind for default agents; infer from model_name presence
  final effectiveKind =
      kind.isEmpty && json.containsKey('model_name') ? 'default' : kind;

  return switch (effectiveKind) {
    'default' => DefaultRoomAgent(
        id: id,
        modelName: _requireString(json, 'model_name', 'default agent'),
        retries: json['retries'] as int? ?? 0,
        systemPrompt: json['system_prompt'] as String?,
        providerType: json['provider_type'] as String? ?? '',
        aguiFeatureNames: aguiFeatureNames,
      ),
    'factory' => FactoryRoomAgent(
        id: id,
        factoryName: _requireString(json, 'factory_name', 'factory agent'),
        extraConfig:
            (json['extra_config'] as Map<String, dynamic>?) ?? const {},
        aguiFeatureNames: aguiFeatureNames,
      ),
    _ => OtherRoomAgent(id: id, kind: kind, aguiFeatureNames: aguiFeatureNames),
  };
}

/// Extracts a required string field, throwing [FormatException] if missing
/// or not a string.
String _requireString(Map<String, dynamic> json, String field, String context) {
  final value = json[field];
  if (value is! String) {
    throw FormatException('$context JSON missing required "$field" field');
  }
  return value;
}

/// Creates a [RoomTool] from JSON.
RoomTool roomToolFromJson(String name, Map<String, dynamic> json) {
  return RoomTool(
    name: (json['tool_name'] as String?) ?? name,
    description: (json['tool_description'] as String?) ?? '',
    kind: (json['kind'] as String?) ?? '',
    toolRequires: (json['tool_requires'] as String?) ?? '',
    allowMcp: json['allow_mcp'] as bool? ?? false,
    extraParameters:
        (json['extra_parameters'] as Map<String, dynamic>?) ?? const {},
    aguiFeatureNames: _parseStringList(
      json['agui_feature_names'] as List<dynamic>?,
    ),
  );
}

/// Creates a [McpClientToolset] from JSON.
McpClientToolset mcpClientToolsetFromJson(Map<String, dynamic> json) {
  final allowedToolsRaw = json['allowed_tools'] as List<dynamic>?;
  return McpClientToolset(
    kind: json['kind'] as String? ?? '',
    allowedTools: allowedToolsRaw?.whereType<String>().toList(),
    toolsetParams:
        (json['toolset_params'] as Map<String, dynamic>?) ?? const {},
  );
}

/// Creates a [RoomSkill] from JSON.
RoomSkill roomSkillFromJson(String key, Map<String, dynamic> json) {
  return RoomSkill(
    name: (json['name'] as String?) ?? key,
    description: (json['description'] as String?) ?? '',
    source: json['source'] as String?,
    license: json['license'] as String?,
    compatibility: json['compatibility'] as String?,
    allowedTools: _splitAllowedTools(json['allowed_tools'] as String?),
    stateNamespace: json['state_namespace'] as String?,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    stateTypeSchema: json['state_type_schema'] as Map<String, dynamic>?,
  );
}

/// Splits a space-separated allowed-tools string into a list.
List<String>? _splitAllowedTools(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return raw.split(' ').where((s) => s.isNotEmpty).toList();
}

/// Converts a [RoomSkill] to JSON.
Map<String, dynamic> roomSkillToJson(RoomSkill skill) {
  return {
    'name': skill.name,
    if (skill.description.isNotEmpty) 'description': skill.description,
    if (skill.source != null) 'source': skill.source,
    if (skill.license != null) 'license': skill.license,
    if (skill.compatibility != null) 'compatibility': skill.compatibility,
    if (skill.allowedTools != null)
      'allowed_tools': skill.allowedTools!.join(' '),
    if (skill.stateNamespace != null) 'state_namespace': skill.stateNamespace,
    if (skill.metadata.isNotEmpty) 'metadata': skill.metadata,
    if (skill.stateTypeSchema != null)
      'state_type_schema': skill.stateTypeSchema,
  };
}

/// Parses a timestamp string, returning null on failure.
DateTime? _tryParseTimestamp(String? raw) {
  if (raw == null) return null;
  try {
    return parseTimestamp(raw);
  } on FormatException catch (e) {
    developer.log(
      'Malformed timestamp ignored: $e',
      name: 'soliplex_client.document',
      level: 900,
    );
    return null;
  }
}

/// Parses a dynamic list into a list of strings,
/// filtering out non-string items.
List<String> _parseStringList(List<dynamic>? raw) {
  if (raw == null) return const [];
  return raw.whereType<String>().toList();
}

/// Creates a [Room] from JSON.
Room roomFromJson(Map<String, dynamic> json) {
  // Extract quizzes map: {quizId: {title: "...", ...}}
  final quizzesJson = json['quizzes'] as Map<String, dynamic>?;
  final quizzes = <String, String>{};
  if (quizzesJson != null) {
    for (final entry in quizzesJson.entries) {
      final quizData = entry.value as Map<String, dynamic>?;
      final title = (quizData?['title'] as String?) ?? 'Quiz';
      quizzes[entry.key] = title;
    }
  }

  final suggestionsRaw = json['suggestions'] as List<dynamic>?;
  final suggestions = <String>[];
  if (suggestionsRaw != null) {
    for (final item in suggestionsRaw) {
      if (item is String) {
        suggestions.add(item);
      } else {
        developer.log(
          'Non-string suggestion ignored: '
          '$item (${item.runtimeType})',
          name: 'soliplex_client.room',
          level: 900, // Warning level
        );
      }
    }
  }

  // Parse agent — malformed agent data should not prevent the room from loading
  final agentJson = json['agent'] as Map<String, dynamic>?;
  RoomAgent? agent;
  if (agentJson != null) {
    try {
      agent = roomAgentFromJson(agentJson);
    } on FormatException catch (e) {
      developer.log(
        'Malformed agent ignored: $e\n$agentJson',
        name: 'soliplex_client.room',
        level: 900,
      );
    }
  }

  // Parse tools — accept Map (backend) or List (fallback) format
  final rawTools = json['tools'];
  final tools = <String, RoomTool>{};
  final toolDefinitions = <Map<String, dynamic>>[];
  if (rawTools is Map<String, dynamic>) {
    for (final entry in rawTools.entries) {
      if (entry.value is! Map<String, dynamic>) {
        developer.log(
          'Malformed tool ignored: ${entry.key}\n${entry.value}',
          name: 'soliplex_client.room',
          level: 900,
        );
        continue;
      }
      tools[entry.key] = roomToolFromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
      toolDefinitions.add(entry.value as Map<String, dynamic>);
    }
  } else if (rawTools is List) {
    for (final item in rawTools) {
      if (item is Map<String, dynamic>) {
        toolDefinitions.add(item);
      }
    }
  }

  // Parse MCP client toolsets — skip malformed entries
  final mcpJson = json['mcp_client_toolsets'] as Map<String, dynamic>?;
  final mcpClientToolsets = <String, McpClientToolset>{};
  if (mcpJson != null) {
    for (final entry in mcpJson.entries) {
      if (entry.value is! Map<String, dynamic>) {
        developer.log(
          'Malformed MCP toolset ignored: ${entry.key}\n${entry.value}',
          name: 'soliplex_client.room',
          level: 900,
        );
        continue;
      }
      mcpClientToolsets[entry.key] = mcpClientToolsetFromJson(
        entry.value as Map<String, dynamic>,
      );
    }
  }

  // Parse skills — skip malformed entries
  final skillsJson = json['skills'] as Map<String, dynamic>?;
  final skills = <String, RoomSkill>{};
  if (skillsJson != null) {
    for (final entry in skillsJson.entries) {
      if (entry.value is! Map<String, dynamic>) {
        developer.log(
          'Malformed skill ignored: ${entry.key}\n${entry.value}',
          name: 'soliplex_client.room',
          level: 900,
        );
        continue;
      }
      skills[entry.key] = roomSkillFromJson(
        entry.key,
        entry.value as Map<String, dynamic>,
      );
    }
  }

  return Room(
    id: _requireString(json, 'id', 'room'),
    name: _requireString(json, 'name', 'room'),
    description: (json['description'] as String?) ?? '',
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    quizzes: quizzes,
    suggestions: suggestions,
    welcomeMessage: (json['welcome_message'] as String?) ?? '',
    enableAttachments: json['enable_attachments'] as bool? ?? false,
    allowMcp: json['allow_mcp'] as bool? ?? false,
    agent: agent,
    skills: skills,
    tools: tools,
    mcpClientToolsets: mcpClientToolsets,
    toolDefinitions: toolDefinitions,
    aguiFeatureNames: _parseStringList(
      json['agui_feature_names'] as List<dynamic>?,
    ),
  );
}

/// Converts a [Room] to JSON.
///
/// This is a partial serialization — fields like [Room.agent],
/// [Room.mcpClientToolsets], [Room.allowMcp], and [Room.suggestions]
/// are not yet serialized. Add them here when round-trip fidelity is needed.
Map<String, dynamic> roomToJson(Room room) {
  return {
    'id': room.id,
    'name': room.name,
    if (room.description.isNotEmpty) 'description': room.description,
    if (room.metadata.isNotEmpty) 'metadata': room.metadata,
    if (room.welcomeMessage.isNotEmpty) 'welcome_message': room.welcomeMessage,
    if (room.enableAttachments) 'enable_attachments': room.enableAttachments,
    if (room.skills.isNotEmpty)
      'skills': {
        for (final entry in room.skills.entries)
          entry.key: roomSkillToJson(entry.value),
      },
    if (room.toolDefinitions.isNotEmpty)
      'tools': {
        for (final tool in room.toolDefinitions)
          (tool['tool_name'] as String? ?? tool['name'] as String? ?? ''): tool,
      },
    if (room.aguiFeatureNames.isNotEmpty)
      'agui_feature_names': room.aguiFeatureNames,
  };
}

// ============================================================
// RagDocument mappers
// ============================================================

/// Creates a [RagDocument] from JSON.
RagDocument ragDocumentFromJson(Map<String, dynamic> json) {
  final uri = (json['uri'] as String?) ?? '';
  // title can be null - fall back to uri, then 'Untitled'
  final title =
      (json['title'] as String?) ?? (uri.isNotEmpty ? uri : 'Untitled');

  final createdRaw = json['created_at'] as String?;
  final updatedRaw = json['updated_at'] as String?;

  return RagDocument(
    id: _requireString(json, 'id', 'document'),
    title: title,
    uri: uri,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
    createdAt: _tryParseTimestamp(createdRaw),
    updatedAt: _tryParseTimestamp(updatedRaw),
  );
}

/// Converts a [RagDocument] to JSON.
Map<String, dynamic> ragDocumentToJson(RagDocument doc) {
  return {
    'id': doc.id,
    'title': doc.title,
    if (doc.uri.isNotEmpty) 'uri': doc.uri,
    if (doc.metadata.isNotEmpty) 'metadata': doc.metadata,
    if (doc.createdAt != null) 'created_at': formatTimestamp(doc.createdAt!),
    if (doc.updatedAt != null) 'updated_at': formatTimestamp(doc.updatedAt!),
  };
}

// ============================================================
// ThreadInfo mappers
// ============================================================

/// Creates a [ThreadInfo] from JSON.
///
/// Throws [FormatException] if required fields are missing or malformed.
ThreadInfo threadInfoFromJson(Map<String, dynamic> json) {
  final createdRaw = json['created'] as String?;
  if (createdRaw == null) {
    throw FormatException('Thread ${json['id']} missing required "created"');
  }
  final createdAt = parseTimestamp(createdRaw);

  // Name/description may be at top level or nested in metadata
  final metadata = (json['metadata'] as Map<String, dynamic>?) ?? const {};
  final name = (json['name'] as String?) ?? (metadata['name'] as String?) ?? '';
  final description = (json['description'] as String?) ??
      (metadata['description'] as String?) ??
      '';

  return ThreadInfo(
    id: json['id'] as String? ?? json['thread_id'] as String,
    roomId: json['room_id'] as String? ?? '',
    initialRunId: (json['initial_run_id'] as String?) ?? '',
    name: name,
    description: description,
    createdAt: createdAt,
    metadata: metadata,
  );
}

/// Converts a [ThreadInfo] to JSON.
Map<String, dynamic> threadInfoToJson(ThreadInfo thread) {
  return {
    'id': thread.id,
    'room_id': thread.roomId,
    if (thread.initialRunId.isNotEmpty) 'initial_run_id': thread.initialRunId,
    if (thread.name.isNotEmpty) 'name': thread.name,
    if (thread.description.isNotEmpty) 'description': thread.description,
    'created': formatTimestamp(thread.createdAt),
    if (thread.metadata.isNotEmpty) 'metadata': thread.metadata,
  };
}

/// Converts thread metadata fields to the backend JSON format.
///
/// Only includes non-null fields. The backend replaces all metadata on
/// update — omitted fields are dropped, not preserved.
Map<String, dynamic> threadMetadataToJson({
  String? name,
  String? description,
}) {
  return {
    if (name != null) 'name': name,
    if (description != null) 'description': description,
  };
}

// ============================================================
// RunInfo mappers
// ============================================================

/// Creates a [RunInfo] from JSON.
///
/// Throws [FormatException] if required fields are missing or malformed.
RunInfo runInfoFromJson(Map<String, dynamic> json) {
  final createdRaw = json['created'] as String?;
  if (createdRaw == null) {
    throw FormatException('Run ${json['id']} missing required "created"');
  }

  return RunInfo(
    id: json['id'] as String? ?? json['run_id'] as String,
    threadId: json['thread_id'] as String? ?? '',
    label: (json['label'] as String?) ?? '',
    createdAt: parseTimestamp(createdRaw),
    completion: json['completed_at'] != null
        ? CompletedAt(parseTimestamp(json['completed_at'] as String))
        : const NotCompleted(),
    status: runStatusFromString(json['status'] as String?),
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? const {},
  );
}

/// Converts a [RunInfo] to JSON.
Map<String, dynamic> runInfoToJson(RunInfo run) {
  return {
    'id': run.id,
    'thread_id': run.threadId,
    if (run.label.isNotEmpty) 'label': run.label,
    'created': formatTimestamp(run.createdAt),
    if (run.completion case CompletedAt(:final time))
      'completed_at': formatTimestamp(time),
    'status': run.status.name,
    if (run.metadata.isNotEmpty) 'metadata': run.metadata,
  };
}

/// Creates a [RunStatus] from a string value.
///
/// Returns [RunStatus.pending] if value is null.
/// Returns [RunStatus.unknown] if value doesn't match any known status.
RunStatus runStatusFromString(String? value) {
  if (value == null) return RunStatus.pending;
  return RunStatus.values.firstWhere(
    (e) => e.name == value.toLowerCase(),
    orElse: () => RunStatus.unknown,
  );
}

// ============================================================
// Quiz mappers
// ============================================================

/// Creates a [QuestionType] from JSON metadata.
///
/// Unknown question types fall back to [FreeForm] with a warning logged.
/// This provides graceful degradation when the backend adds new types that
/// the client doesn't yet support - users can still answer via text input.
QuestionType questionTypeFromJson(Map<String, dynamic> json) {
  final type = json['type'] as String;
  return switch (type) {
    'multiple-choice' || 'multiple_choice' => MultipleChoice(
        (json['options'] as List<dynamic>).cast<String>(),
      ),
    'fill-blank' || 'fill_blank' => const FillBlank(),
    'qa' => const FreeForm(),
    _ => () {
        developer.log(
          'Unknown question type "$type", falling back to FreeForm',
          name: 'soliplex_client.quiz',
          level: 900, // Warning level
        );
        return const FreeForm();
      }(),
  };
}

/// Creates a [QuizQuestion] from JSON.
///
/// Note: The `expected_output` field from JSON is intentionally not mapped.
/// The correct answer is only revealed after submission via [QuizAnswerResult].
QuizQuestion quizQuestionFromJson(Map<String, dynamic> json) {
  final metadata = json['metadata'] as Map<String, dynamic>;
  return QuizQuestion(
    id: metadata['uuid'] as String,
    text: json['inputs'] as String,
    type: questionTypeFromJson(metadata),
  );
}

/// Creates a [QuestionLimit] from a nullable max_questions value.
QuestionLimit questionLimitFromJson(int? maxQuestions) {
  if (maxQuestions == null) return const AllQuestions();
  return LimitedQuestions(maxQuestions);
}

/// Creates a [Quiz] from JSON.
Quiz quizFromJson(Map<String, dynamic> json) {
  final questions = (json['questions'] as List<dynamic>)
      .map((q) => quizQuestionFromJson(q as Map<String, dynamic>))
      .toList();

  return Quiz(
    id: json['id'] as String,
    title: json['title'] as String,
    randomize: json['randomize'] as bool? ?? false,
    questionLimit: questionLimitFromJson(json['max_questions'] as int?),
    questions: questions,
  );
}

/// Creates a [QuizAnswerResult] from JSON.
QuizAnswerResult quizAnswerResultFromJson(Map<String, dynamic> json) {
  final correct = json['correct'] as String;
  final expectedOutput = json['expected_output'] as String?;

  return switch (correct) {
    'true' => const CorrectAnswer(),
    'false' => IncorrectAnswer(
        expectedAnswer: expectedOutput ??
            () {
              developer.log(
                'Missing expected_output for incorrect answer',
                name: 'soliplex_client.quiz',
                level: 900, // Warning level
              );
              return '(correct answer not provided)';
            }(),
      ),
    _ => throw FormatException('Invalid correct value: $correct'),
  };
}
