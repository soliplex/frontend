import 'package:collection/collection.dart' show ListEquality, MapEquality;
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
  /// Creates a scope from the names each namespace lists, in the order the
  /// namespaces are given. [names] is their union in first-seen order.
  RagDatabaseScope({
    required Map<String, List<String>> byNamespace,
    List<String> missing = const [],
  })  : _byNamespace = Map.unmodifiable({
          for (final entry in byNamespace.entries)
            entry.key: List<String>.unmodifiable(entry.value),
        }),
        names = List.unmodifiable(
          {for (final list in byNamespace.values) ...list},
        ),
        namespaces = List.unmodifiable(byNamespace.keys),
        missing = List.unmodifiable(missing);

  /// Reads the scope from [room]'s skills.
  ///
  /// A skill whose `database_names` is missing, of the wrong shape, or carries
  /// non-string entries contributes what can be read and nothing else: the
  /// manifest is display data here, and understating a room's databases only
  /// hides the selector.
  factory RagDatabaseScope.of(Room room) {
    final byNamespace = <String, List<String>>{};
    final missing = <String>[];
    for (final skill in room.skills.values) {
      final namespace = skill.stateNamespace;
      if (namespace == null) continue;
      for (final entry in _databaseNames(skill)) {
        if (entry.startsWith(ragMissingDatabasePrefix)) {
          final name = entry.substring(ragMissingDatabasePrefix.length);
          if (name.isNotEmpty && !missing.contains(name)) missing.add(name);
          continue;
        }
        // A namespace is only recorded once it has a name to search: one
        // whose every database is missing has nothing a selection could
        // legally name, so nothing is written to it.
        final names = byNamespace.putIfAbsent(namespace, () => []);
        if (!names.contains(entry)) names.add(entry);
      }
    }
    if (byNamespace.isEmpty && missing.isEmpty) return none;
    return RagDatabaseScope(byNamespace: byNamespace, missing: missing);
  }

  /// A room with no RAG skill, or none that names a database.
  static final RagDatabaseScope none = RagDatabaseScope(byNamespace: const {});

  final Map<String, List<String>> _byNamespace;

  /// Database names in first-seen order across the room's skills, without
  /// repeats. The name is the backend's public identity for a database — what
  /// search hits and citations report — never a path.
  final List<String> names;

  /// The state namespaces (`rag`, `analysis`) of the skills naming a
  /// database, in the same order. A selection is written to each — but only
  /// the part of it that namespace can search, see [namesFor].
  final List<String> namespaces;

  /// The names [namespace] searches, in manifest order; empty for one the
  /// scope does not carry. Two skills over different sets each read their
  /// own, and a name one of them does not list would fail its run.
  List<String> namesFor(String namespace) =>
      _byNamespace[namespace] ?? const [];

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
  static const _mapEquality =
      MapEquality<String, List<String>>(values: _equality);

  @override
  bool operator ==(Object other) =>
      other is RagDatabaseScope &&
      _mapEquality.equals(other._byNamespace, _byNamespace) &&
      _equality.equals(other.missing, missing);

  @override
  int get hashCode =>
      Object.hash(_mapEquality.hash(_byNamespace), _equality.hash(missing));

  @override
  String toString() =>
      'RagDatabaseScope(byNamespace: $_byNamespace, missing: $missing)';
}
