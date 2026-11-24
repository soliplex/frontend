import 'package:meta/meta.dart';

/// What a reload of the installation's room configs changed, as room ids.
///
/// All three empty means the configs on disk already matched what the server
/// was serving.
@immutable
class RoomConfigsReloaded {
  /// Creates a reload result.
  const RoomConfigsReloaded({
    this.added = const [],
    this.removed = const [],
    this.changed = const [],
  });

  /// Rooms the reload made available.
  final List<String> added;

  /// Rooms the reload withdrew.
  final List<String> removed;

  /// Rooms whose config the reload replaced.
  final List<String> changed;

  /// Whether the reload changed nothing.
  bool get isEmpty => added.isEmpty && removed.isEmpty && changed.isEmpty;
}
