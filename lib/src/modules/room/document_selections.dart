import 'package:soliplex_client/soliplex_client.dart';

/// Persists per-thread document filter selections across navigation.
///
/// Keyed by (roomId, threadId) so selections survive room switches.
/// Lives above RoomScreen in the dependency graph — created once at the
/// module level and injected via constructor.
class DocumentSelections {
  final _selections = <(String, String?), Set<RagDocument>>{};

  Set<RagDocument> get(String roomId, String? threadId) =>
      _selections[(roomId, threadId)] ?? const {};

  void set(String roomId, String? threadId, Set<RagDocument> docs) {
    if (docs.isEmpty) {
      _selections.remove((roomId, threadId));
    } else {
      _selections[(roomId, threadId)] = docs;
    }
  }

  /// Moves the selection from the null-thread key to [threadId].
  ///
  /// Used when a user selects documents before a thread exists, then
  /// a thread is created implicitly by sending a message.
  void migrateToThread(String roomId, String threadId) {
    final pending = _selections.remove((roomId, null));
    if (pending != null && pending.isNotEmpty) {
      _selections[(roomId, threadId)] = pending;
    }
  }
}
