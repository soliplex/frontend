import 'package:meta/meta.dart';

/// A category that can be attached to threads.
///
/// Labels are global to a server — one namespace shared by every room —
/// and are curated by administrators; anyone may attach an existing one
/// to their own threads, but only an administrator may create, rename,
/// recolour or delete.
@immutable
class ThreadLabel {
  /// Creates a label.
  const ThreadLabel({
    required this.id,
    required this.name,
    required this.color,
    this.usageCount,
  });

  /// Unique identifier, allocated by the server.
  ///
  /// This is the comparison key: filtering and equality go through the
  /// integer, and [name] is only ever for humans. IDs are allocated per
  /// deployment, so nothing that travels between servers may key on one.
  final int id;

  /// Display name, as people read and type it.
  ///
  /// Names ignore case: `Urgent` and `urgent` are the same label, so
  /// matching one typed by a user must fold case too.
  final String name;

  /// `#RRGGBB` swatch for the label's chip.
  final String color;

  /// How many threads carry this label, or `null` when the server did
  /// not say.
  ///
  /// The count spans every user's threads, so the server sends it only
  /// to administrators. `null` therefore means "not allowed to know",
  /// which is emphatically not the same as zero — treating it as zero
  /// would offer a delete as harmless when it is anything but.
  final int? usageCount;

  /// Creates a copy of this label with the given fields replaced.
  ThreadLabel copyWith({
    int? id,
    String? name,
    String? color,
    int? usageCount,
  }) {
    return ThreadLabel(
      id: id ?? this.id,
      name: name ?? this.name,
      color: color ?? this.color,
      usageCount: usageCount ?? this.usageCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ThreadLabel &&
        other.id == id &&
        other.name == name &&
        other.color == color &&
        other.usageCount == usageCount;
  }

  @override
  int get hashCode => Object.hash(id, name, color, usageCount);

  @override
  String toString() => 'ThreadLabel(id: $id, name: $name, color: $color)';
}
