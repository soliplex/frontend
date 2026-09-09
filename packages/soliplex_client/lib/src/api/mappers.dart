import 'package:soliplex_client/src/domain/backend_version_info.dart';
import 'package:soliplex_client/src/domain/file_upload.dart';
import 'package:soliplex_client/src/domain/mcp_client_toolset.dart';
import 'package:soliplex_client/src/domain/quiz.dart';
import 'package:soliplex_client/src/domain/rag_document.dart';
import 'package:soliplex_client/src/domain/room.dart';
import 'package:soliplex_client/src/domain/room_agent.dart';
import 'package:soliplex_client/src/domain/room_skill.dart';
import 'package:soliplex_client/src/domain/room_stats.dart';
import 'package:soliplex_client/src/domain/room_tool.dart';
import 'package:soliplex_client/src/domain/run_feedback.dart';
import 'package:soliplex_client/src/domain/run_info.dart';
import 'package:soliplex_client/src/domain/thread_info.dart';
import 'package:soliplex_client/src/domain/workdir_file.dart';
import 'package:soliplex_client/src/utils/parse_utils.dart';
import 'package:soliplex_client/src/utils/source_url.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_client.mappers');

// ============================================================
// Timestamp helpers
// ============================================================

/// Trailing timezone designator: a 'Z' or a numeric offset like '+00:00' /
/// '-05:00'. Anchored to the tail so the hyphens in the date (`2026-06-01`) and
/// the colons in a naive time (`12:30:45`) don't false-match.
final _hasTimezone = RegExp(r'(Z|[+-]\d{2}:\d{2})$');

/// Parses a backend timestamp into a UTC instant.
///
/// Naive ISO 8601 timestamps (no designator) are UTC-but-unmarked, so they get
/// a 'Z'. Offset-tagged values (aware datetimes such as the stats API's
/// `last_activity`, or Postgres-backed fields) already pin the instant and are
/// parsed as-is. The result is always in UTC.
///
/// Throws [FormatException] if [raw] is malformed.
DateTime parseTimestamp(String raw) {
  final normalized = _hasTimezone.hasMatch(raw) ? raw : '${raw}Z';
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
/// Three fields across the agent variants are deliberately not modelled.
///
/// `provider_key` is a secret *reference* of the form `secret:SECRET_NAME`
/// that only the backend's `get_secret()` can resolve, or the placeholder
/// `"dummy"` where a room configured none (`models.py`). Neither is usable
/// here, and the first would put the name of a secret on a screen that can
/// be exported.
///
/// `provider_base_url` is the resolved endpoint URL. The backend interpolates
/// `env:` markers into it (`config/agents.py`) and an environment variable
/// holds whatever an operator puts there, so the resolved value is not known
/// to be safe to display. Nothing renders it, so nothing reads it.
///
/// Neither `provider_key` nor `provider_base_url` is checked for at runtime
/// on purpose. Sniffing a value for
/// credential-shaped content would be a guess that goes stale silently;
/// declining the field is what actually holds.
///
/// `with_agent_config` decides whether the backend hands its factory callable
/// an `agent_config` keyword argument (`config/agents.py`). It is a Python
/// calling convention with no counterpart anyone using this app can observe,
/// so rendering it would put a bare `Yes` on a card whose every other row
/// says what the agent is or does.
RoomAgent roomAgentFromJson(Map<String, dynamic> json) {
  final id = _requireString(json, 'id', 'agent');
  final aguiFeatureNames =
      stringList(json['agui_feature_names'], 'agui_feature_names');

  // The variant is read off the shape, because the wire carries no
  // discriminator to read instead: the backend's `DefaultAgent` and
  // `FactoryAgent` declare no `kind` field, and only `OtherAgent` does.
  // `factory_name`, `model_name` and `provider_type` are each required on
  // exactly one variant, so presence — not value — tells them apart;
  // `model_name` is nullable but pydantic still emits the key.
  //
  // A `kind` of `default` or `factory` cannot reach here today, since the
  // backend sets `kind` only on the variant it could not type. It decides
  // outright where it is present so that a backend which starts sending the
  // discriminator is read by it rather than second-guessed by shape.
  final kind = stringOrNull(json['kind'], 'kind') ?? '';

  if (kind.isNotEmpty) {
    return switch (kind) {
      'factory' => _factoryAgentFromJson(json, id, aguiFeatureNames),
      'default' => _defaultAgentFromJson(json, id, aguiFeatureNames),
      _ => OtherRoomAgent(
          id: id,
          kind: kind,
          aguiFeatureNames: aguiFeatureNames,
        ),
    };
  }

  if (json.containsKey('factory_name')) {
    return _factoryAgentFromJson(json, id, aguiFeatureNames);
  }

  if (json.containsKey('model_name') || json.containsKey('provider_type')) {
    return _defaultAgentFromJson(json, id, aguiFeatureNames);
  }

  return OtherRoomAgent(id: id, kind: kind, aguiFeatureNames: aguiFeatureNames);
}

FactoryRoomAgent _factoryAgentFromJson(
  Map<String, dynamic> json,
  String id,
  List<String> aguiFeatureNames,
) {
  return FactoryRoomAgent(
    id: id,
    factoryName: _requireString(json, 'factory_name', 'factory agent'),
    extraConfig: jsonMap(json['extra_config'], 'extra_config'),
    aguiFeatureNames: aguiFeatureNames,
  );
}

DefaultRoomAgent _defaultAgentFromJson(
  Map<String, dynamic> json,
  String id,
  List<String> aguiFeatureNames,
) {
  return DefaultRoomAgent(
    id: id,
    // Nullable on the wire, and the card omits the row when it is absent.
    modelName: stringOrNull(json['model_name'], 'model_name'),
    retries: intOrNull(json['retries'], 'retries') ?? 0,
    systemPrompt: stringOrNull(json['system_prompt'], 'system_prompt'),
    providerType: stringOrNull(json['provider_type'], 'provider_type') ?? '',
    aguiFeatureNames: aguiFeatureNames,
  );
}

/// Extracts a required string field, throwing [FormatException] if missing
/// or not a string.
///
/// [FormatException] (not MalformedResponseException) is deliberate: these
/// reads sit inside per-entry parsing that an enclosing fail-soft loop —
/// `roomFromJson`'s agent parse, `_parseFileList`'s per-row parse — catches on
/// [FormatException] to skip just the malformed entry. A hard
/// MalformedResponseException would fail the whole response instead. Contrast
/// the top-level required-field reads in `SoliplexApi`, which throw
/// MalformedResponseException by design.
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
    name: stringOrNull(json['tool_name'], 'tool_name') ?? name,
    description:
        stringOrNull(json['tool_description'], 'tool_description') ?? '',
    kind: stringOrNull(json['kind'], 'kind') ?? '',
    toolRequires: stringOrNull(json['tool_requires'], 'tool_requires') ?? '',
    allowMcp: boolOrNull(json['allow_mcp'], 'allow_mcp') ?? false,
    extraParameters: jsonMap(json['extra_parameters'], 'extra_parameters'),
    aguiFeatureNames:
        stringList(json['agui_feature_names'], 'agui_feature_names'),
  );
}

/// Creates a [McpClientToolset] from JSON.
McpClientToolset mcpClientToolsetFromJson(
  String key,
  Map<String, dynamic> json,
) {
  // An absent and an empty allow-list are one state on the backend, whose
  // `_allowed_tools_filter` reads "a None or empty allow-list means expose
  // every tool the server offers" (`mcp_client.py`), so the empty list
  // carries both and no null is needed to tell them apart.
  //
  // An unreadable one also reads as empty, which understates a restriction
  // rather than inventing one. It is logged against the toolset key, because
  // the screen cannot distinguish it and the record is the only way to.
  final raw = json['allowed_tools'];
  final allowedTools = stringList(raw, 'allowed_tools');
  if (raw != null && (raw is! List || raw.length != allowedTools.length)) {
    _logger.warning(
      'Unreadable MCP allow-list, shown as unrestricted',
      attributes: {'toolset': key, 'runtimeType': raw.runtimeType.toString()},
    );
  }
  return McpClientToolset(
    kind: stringOrNull(json['kind'], 'kind') ?? '',
    allowedTools: allowedTools,
    toolsetParams: jsonMap(json['toolset_params'], 'toolset_params'),
  );
}

/// Creates a [RoomSkill] from JSON.
RoomSkill roomSkillFromJson(String key, Map<String, dynamic> json) {
  return RoomSkill(
    name: stringOrNull(json['name'], 'name') ?? key,
    description: stringOrNull(json['description'], 'description') ?? '',
    source: stringOrNull(json['source'], 'source'),
    stateNamespace: stringOrNull(json['state_namespace'], 'state_namespace'),
    extraParameters: jsonMap(json['extra_parameters'], 'extra_parameters'),
    stateTypeSchema: jsonMap(json['state_type_schema'], 'state_type_schema'),
  );
}

/// Converts a [RoomSkill] to JSON.
Map<String, dynamic> roomSkillToJson(RoomSkill skill) {
  return {
    'name': skill.name,
    if (skill.description.isNotEmpty) 'description': skill.description,
    if (skill.source != null) 'source': skill.source,
    if (skill.stateNamespace != null) 'state_namespace': skill.stateNamespace,
    if (skill.extraParameters.isNotEmpty)
      'extra_parameters': skill.extraParameters,
    if (skill.stateTypeSchema.isNotEmpty)
      'state_type_schema': skill.stateTypeSchema,
  };
}

/// Parses a timestamp string, returning null on failure.
///
/// [subsystem] attributes a malformed-timestamp log to the calling subsystem.
DateTime? _tryParseTimestamp(
  String? raw, {
  String subsystem = 'soliplex_client.document',
}) {
  if (raw == null) return null;
  try {
    return parseTimestamp(raw);
  } on FormatException catch (e, stackTrace) {
    // `describeFailure` rather than `error: e`: a date parse puts the string
    // it failed on into `FormatException.source`, and `toString()` renders a
    // window of it.
    _logger.warning(
      'Malformed timestamp ignored',
      stackTrace: stackTrace,
      attributes: {'subsystem': subsystem, 'failure': describeFailure(e)},
    );
    return null;
  }
}

/// Creates a [Room] from JSON.
Room roomFromJson(Map<String, dynamic> json) {
  // Extract quizzes map: {quizId: {title: "...", ...}}
  final quizzes = <String, String>{};
  for (final entry in jsonMap(json['quizzes'], 'quizzes').entries) {
    final quizData = entry.value;
    if (quizData is! Map<String, dynamic>) {
      _logger.warning(
        'Malformed quiz ignored',
        attributes: {
          'quiz': entry.key,
          'runtimeType': quizData.runtimeType.toString(),
        },
      );
      continue;
    }
    // Only the title. The room payload nests each quiz whole, including
    // every question's `expected_output`, which `quizQuestionFromJson`
    // deliberately drops so an answer key never reaches a `Quiz` the UI
    // holds — grading reads it from the answer-submission response instead.
    // Parsing the nested copy here would have to repeat that omission in a
    // second place.
    quizzes[entry.key] = stringOrNull(quizData['title'], 'title') ?? 'Quiz';
  }

  final suggestionsRaw = json['suggestions'];
  final suggestions = <String>[];
  if (suggestionsRaw is List) {
    for (final item in suggestionsRaw) {
      if (item is String) {
        suggestions.add(item);
      } else {
        _logger.warning(
          'Non-string suggestion ignored',
          attributes: {'runtimeType': item.runtimeType.toString()},
        );
      }
    }
  } else if (suggestionsRaw != null) {
    _logger.warning(
      'Malformed suggestions ignored',
      attributes: {'runtimeType': suggestionsRaw.runtimeType.toString()},
    );
  }

  // Parse agent — malformed agent data should not prevent the room from
  // loading, including an agent block that is not a map at all.
  final rawAgent = json['agent'];
  final agentJson = rawAgent is Map<String, dynamic> ? rawAgent : null;
  if (rawAgent != null && agentJson == null) {
    _logger.warning(
      'Malformed agent ignored',
      attributes: {'runtimeType': rawAgent.runtimeType.toString()},
    );
  }
  RoomAgent? agent;
  if (agentJson != null) {
    try {
      agent = roomAgentFromJson(agentJson);
    } on FormatException catch (e, stackTrace) {
      // The agent block carries `provider_key` and `system_prompt`, so it
      // never reaches a sink; `describeFailure` names the field that was
      // missing without echoing the block.
      _logger.warning(
        'Malformed agent ignored',
        stackTrace: stackTrace,
        attributes: {'failure': describeFailure(e)},
      );
    }
  }

  // Parse tools — skip malformed entries
  final tools = <String, RoomTool>{};
  final toolDefinitions = <Map<String, dynamic>>[];
  for (final entry in jsonMap(json['tools'], 'tools').entries) {
    final toolJson = entry.value;
    if (toolJson is! Map<String, dynamic>) {
      _logger.warning(
        'Malformed tool ignored',
        attributes: {
          'tool': entry.key,
          'runtimeType': toolJson.runtimeType.toString(),
        },
      );
      continue;
    }
    tools[entry.key] = roomToolFromJson(entry.key, toolJson);
    toolDefinitions.add(toolJson);
  }

  // Parse MCP client toolsets — skip malformed entries
  final mcpJson = jsonMap(json['mcp_client_toolsets'], 'mcp_client_toolsets');
  final mcpClientToolsets = <String, McpClientToolset>{};
  for (final entry in mcpJson.entries) {
    if (entry.value is! Map<String, dynamic>) {
      _logger.warning(
        'Malformed MCP toolset ignored',
        attributes: {
          'toolset': entry.key,
          'runtimeType': entry.value.runtimeType.toString(),
        },
      );
      continue;
    }
    mcpClientToolsets[entry.key] = mcpClientToolsetFromJson(
      entry.key,
      entry.value as Map<String, dynamic>,
    );
  }

  // Parse skills — skip malformed entries
  final skillsJson = jsonMap(json['skills'], 'skills');
  final skills = <String, RoomSkill>{};
  for (final entry in skillsJson.entries) {
    if (entry.value is! Map<String, dynamic>) {
      _logger.warning(
        'Malformed skill ignored',
        attributes: {
          'skill': entry.key,
          'runtimeType': entry.value.runtimeType.toString(),
        },
      );
      continue;
    }
    skills[entry.key] = roomSkillFromJson(
      entry.key,
      entry.value as Map<String, dynamic>,
    );
  }

  return Room(
    id: _requireString(json, 'id', 'room'),
    name: _requireString(json, 'name', 'room'),
    description: stringOrNull(json['description'], 'description') ?? '',
    quizzes: quizzes,
    suggestions: suggestions,
    welcomeMessage:
        stringOrNull(json['welcome_message'], 'welcome_message') ?? '',
    allowMcp: boolOrNull(json['allow_mcp'], 'allow_mcp') ?? false,
    agent: agent,
    skills: skills,
    tools: tools,
    mcpClientToolsets: mcpClientToolsets,
    toolDefinitions: toolDefinitions,
    aguiFeatureNames:
        stringList(json['agui_feature_names'], 'agui_feature_names'),
    // Absent — or wrongly typed — reads as no capability, which withholds
    // every upload control. That is a default, not a deduction: a server too
    // old to publish these can still have upload paths configured, and
    // nothing readable here distinguishes it from a server that has none.
    // [roomOmitsUploadCapability] is what lets a caller record the difference.
    acceptsRoomUploads:
        boolOrNull(json[_roomUploadsKey], _roomUploadsKey) ?? false,
    acceptsThreadUploads:
        boolOrNull(json[_threadUploadsKey], _threadUploadsKey) ?? false,
  );
}

/// The rooms API's per-scope upload capability keys.
///
/// Named once so the reader below cannot drift from the parser above.
const _roomUploadsKey = 'has_room_uploads';
const _threadUploadsKey = 'has_thread_uploads';

/// Whether a room payload reported neither upload scope.
///
/// Absent and explicitly null read alike, because both mean the server did not
/// say and both withhold every upload control. A present-but-wrongly-typed
/// value is not an omission and is left to [boolOrNull], which records it
/// against the field it arrived in.
bool roomOmitsUploadCapability(Map<String, dynamic> json) =>
    json[_roomUploadsKey] == null && json[_threadUploadsKey] == null;

/// Converts a [Room] to JSON.
///
/// This is a partial serialization — [Room.agent], [Room.mcpClientToolsets],
/// [Room.allowMcp], [Room.suggestions], [Room.quizzes], [Room.tools],
/// [Room.acceptsRoomUploads] and [Room.acceptsThreadUploads] are not
/// serialized. Add them here when round-trip fidelity is needed; until then a
/// round trip reports a room as accepting no uploads.
Map<String, dynamic> roomToJson(Room room) {
  return {
    'id': room.id,
    'name': room.name,
    if (room.description.isNotEmpty) 'description': room.description,
    if (room.welcomeMessage.isNotEmpty) 'welcome_message': room.welcomeMessage,
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

  final createdRaw = json['created_at'] as String?;
  final updatedRaw = json['updated_at'] as String?;

  final metadata = jsonMap(json['metadata'], 'metadata');
  if (hasMalformedSourceUrl(metadata)) {
    _logger.warning('Document source_url present but not a launchable web URL');
  }

  return RagDocument(
    id: _requireString(json, 'id', 'document'),
    title: json['title'] as String?,
    uri: uri,
    metadata: metadata,
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
// FileUpload mappers
// ============================================================

/// Creates a [FileUpload] from JSON.
///
/// Throws [FormatException] if `filename` or `url` is missing or
/// malformed.
FileUpload fileUploadFromJson(Map<String, dynamic> json) {
  return FileUpload(
    filename: _requireString(json, 'filename', 'file upload'),
    url: Uri.parse(_requireString(json, 'url', 'file upload')),
  );
}

// ============================================================
// WorkdirFile mappers
// ============================================================

/// Creates a [WorkdirFile] from JSON.
///
/// Throws [FormatException] if `filename` is missing, empty, contains a
/// path separator, or contains a NUL byte; or if `url` is missing or
/// malformed.
WorkdirFile workdirFileFromJson(Map<String, dynamic> json) {
  final filename = _requireString(json, 'filename', 'workdir file');
  if (filename.isEmpty) {
    throw const FormatException('workdir file filename must not be empty');
  }
  if (filename.contains('/')) {
    throw FormatException(
      'workdir file filename must not contain path separators: $filename',
    );
  }
  if (filename.contains('\x00')) {
    throw const FormatException(
      'workdir file filename must not contain NUL bytes',
    );
  }
  return WorkdirFile(
    filename: filename,
    url: Uri.parse(_requireString(json, 'url', 'workdir file')),
  );
}

// ============================================================
// RoomStats mappers
// ============================================================

/// Creates a [RoomStats] from JSON.
///
/// An absent, null, non-string, or malformed `last_activity` yields a null
/// activity rather than throwing, so one bad field never drops the entry.
RoomStats roomStatsFromJson(Map<String, dynamic> json) {
  final rawActivity = json['last_activity'];
  if (rawActivity != null && rawActivity is! String) {
    // Present but wrong-typed (e.g. a backend switch to an epoch int): degrade
    // to null like a malformed string, but log it — an absent/null field is a
    // legitimate "no activity", a wrong type is a contract drift worth a trace.
    _logger.warning(
      'Non-string last_activity ignored',
      attributes: {'runtimeType': rawActivity.runtimeType.toString()},
    );
  }
  return RoomStats(
    lastActivity: rawActivity is String
        ? _tryParseTimestamp(rawActivity, subsystem: 'soliplex_client.api')
        : null,
  );
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

  // Optional: absent on a pre-stats backend, null when the thread has no
  // runs. A malformed value degrades to null rather than failing the whole
  // listing (mirrors roomStatsFromJson).
  final rawActivity = json['last_activity'];
  final lastActivity = rawActivity is String
      ? _tryParseTimestamp(rawActivity, subsystem: 'soliplex_client.api')
      : null;

  return ThreadInfo(
    id: json['id'] as String? ?? json['thread_id'] as String,
    roomId: json['room_id'] as String? ?? '',
    initialRunId: (json['initial_run_id'] as String?) ?? '',
    name: name,
    description: description,
    createdAt: createdAt,
    metadata: metadata,
    lastActivity: lastActivity,
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
    if (thread.lastActivity != null)
      'last_activity': formatTimestamp(thread.lastActivity!),
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
// Run feedback mappers
// ============================================================

/// Creates a [RunFeedback] from JSON.
///
/// The record's `feedback` rating is deliberately not decoded: the only reader
/// is the dialog that prefills the reason, and a field nothing consumes is a
/// field that rots. Decode it here when a caller needs the rating.
RunFeedback runFeedbackFromJson(Map<String, dynamic> json) {
  return RunFeedback(reason: json['reason'] as String?);
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
        _logger.warning(
          'Unknown question type, falling back to FreeForm',
          attributes: {'questionType': type},
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
              _logger.warning(
                'Missing expected_output for incorrect answer',
              );
              return '(correct answer not provided)';
            }(),
      ),
    _ => throw FormatException('Invalid correct value: $correct'),
  };
}
