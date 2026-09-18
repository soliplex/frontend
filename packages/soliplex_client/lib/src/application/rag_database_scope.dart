import 'package:collection/collection.dart' show ListEquality;
import 'package:meta/meta.dart';
import 'package:soliplex_client/src/domain/room.dart';
import 'package:soliplex_client/src/domain/room_skill.dart';

/// The key under a RAG skill's `extra_parameters` that lists the names of the
/// databases the skill searches. Written by the backend's
/// `_RAGDatabasesBase.get_extra_parameters`.
const String ragDatabaseNamesKey = 'database_names';

/// The prefix the backend puts on a name in `database_names` whose database
/// could not be found on disk (`RAGDatabaseEntry.database_name`). It marks the
/// entry for an operator reading the manifest; the name itself is what
/// follows it, and a search naming the marked form fails the run.
const String ragMissingDatabasePrefix = 'MISSING: ';

/// The RAG databases a room's haiku.rag skills search, and the AG-UI state
/// namespaces a selection among them has to be written to.
///
/// A skill names its databases in the room manifest, under
/// `extra_parameters.database_names`, and reads a per-thread selection from
/// `state.<namespace>.sources`. Only skills carrying a state namespace take
/// part: the legacy `search_documents` tool also lists its databases but reads
/// no AG-UI state, so a selection would silently not apply to it.
@immutable
class RagDatabaseScope {
  /// Creates a scope over [names], selected through [namespaces].
  RagDatabaseScope({
    required List<String> names,
    required List<String> namespaces,
    List<String> missing = const [],
  })  : names = List.unmodifiable(names),
        namespaces = List.unmodifiable(namespaces),
        missing = List.unmodifiable(missing);

  /// Reads the scope from [room]'s skills.
  ///
  /// A skill whose `database_names` is missing, of the wrong shape, or carries
  /// non-string entries contributes what can be read and nothing else: the
  /// manifest is display data here, and understating a room's databases only
  /// hides the selector.
  factory RagDatabaseScope.of(Room room) {
    final names = <String>[];
    final namespaces = <String>[];
    final missing = <String>[];
    for (final skill in room.skills.values) {
      final namespace = skill.stateNamespace;
      if (namespace == null) continue;
      final skillNames = _databaseNames(skill);
      if (skillNames.isEmpty) continue;
      if (!namespaces.contains(namespace)) namespaces.add(namespace);
      for (final entry in skillNames) {
        if (entry.startsWith(ragMissingDatabasePrefix)) {
          final name = entry.substring(ragMissingDatabasePrefix.length);
          if (name.isNotEmpty && !missing.contains(name)) missing.add(name);
        } else if (!names.contains(entry)) {
          names.add(entry);
        }
      }
    }
    if (names.isEmpty && missing.isEmpty) return none;
    return RagDatabaseScope(
      names: names,
      namespaces: namespaces,
      missing: missing,
    );
  }

  /// A room with no RAG skill, or none that names a database.
  static final RagDatabaseScope none =
      RagDatabaseScope(names: const [], namespaces: const []);

  /// Database names in first-seen order across the room's skills, without
  /// repeats. The name is the backend's public identity for a database — what
  /// search hits and citations report — never a path.
  final List<String> names;

  /// The state namespaces (`rag`, `analysis`) of the skills naming a
  /// database, in the same order. A selection is written to each.
  final List<String> namespaces;

  /// Names the manifest marked with [ragMissingDatabasePrefix]: configured,
  /// but not found on disk when the room was read. Kept apart from [names]
  /// so they are never offered or sent — a run naming one fails.
  final List<String> missing;

  /// Whether there is a choice to make: a single database is searched
  /// whether or not it is selected, so nothing is offered for it.
  bool get isSelectable => names.length > 1;

  static List<String> _databaseNames(RoomSkill skill) {
    final raw = skill.extraParameters[ragDatabaseNamesKey];
    if (raw is! List) return const [];
    return [
      for (final entry in raw)
        if (entry is String && entry.isNotEmpty) entry,
    ];
  }

  static const _equality = ListEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is RagDatabaseScope &&
      _equality.equals(other.names, names) &&
      _equality.equals(other.namespaces, namespaces) &&
      _equality.equals(other.missing, missing);

  @override
  int get hashCode => Object.hash(
        _equality.hash(names),
        _equality.hash(namespaces),
        _equality.hash(missing),
      );

  @override
  String toString() => 'RagDatabaseScope(names: $names, '
      'namespaces: $namespaces, missing: $missing)';
}
