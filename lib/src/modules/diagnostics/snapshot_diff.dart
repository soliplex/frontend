import 'package:flutter/foundation.dart';

/// One categorised change between two state snapshots.
@immutable
sealed class SnapshotChange {
  const SnapshotChange(this.path);

  /// Slash-joined JSON path, e.g. `/ui/narrations/0/text`.
  final String path;
}

class AddedChange extends SnapshotChange {
  const AddedChange(super.path, this.value);
  final dynamic value;
}

class RemovedChange extends SnapshotChange {
  const RemovedChange(super.path, this.value);
  final dynamic value;
}

class ReplacedChange extends SnapshotChange {
  const ReplacedChange(super.path, this.before, this.after);
  final dynamic before;
  final dynamic after;
}

/// Result of diffing two `Map<String, dynamic>` snapshots, broken out
/// into added / removed / replaced for UI rendering.
@immutable
class SnapshotDiff {
  const SnapshotDiff({
    required this.added,
    required this.removed,
    required this.replaced,
  });

  const SnapshotDiff.empty()
      : added = const [],
        removed = const [],
        replaced = const [];

  final List<AddedChange> added;
  final List<RemovedChange> removed;
  final List<ReplacedChange> replaced;

  bool get isEmpty => added.isEmpty && removed.isEmpty && replaced.isEmpty;

  int get totalChanges => added.length + removed.length + replaced.length;

  /// Compact summary like `+2 / -1 / ~3` for tile rendering. Empty
  /// segments are dropped (so `+1` / `~2` etc.).
  String get summary {
    final parts = <String>[
      if (added.isNotEmpty) '+${added.length}',
      if (removed.isNotEmpty) '-${removed.length}',
      if (replaced.isNotEmpty) '~${replaced.length}',
    ];
    return parts.isEmpty ? 'no change' : parts.join(' / ');
  }
}

/// Compute the structural diff between two snapshots.
///
/// Pass `null` for [prior] to treat the comparison as "everything in
/// [current] is new" — produces an `AddedChange` per top-level key.
/// Recurses into nested maps; lists are compared by index. Leaf values
/// are compared with `==`. Type mismatches at a path are recorded as a
/// single replacement (no further recursion into the mismatched value).
SnapshotDiff diffSnapshots(
  Map<String, dynamic>? prior,
  Map<String, dynamic> current,
) {
  final added = <AddedChange>[];
  final removed = <RemovedChange>[];
  final replaced = <ReplacedChange>[];
  _diffMap(prior ?? const {}, current, '', added, removed, replaced);
  return SnapshotDiff(
    added: List.unmodifiable(added),
    removed: List.unmodifiable(removed),
    replaced: List.unmodifiable(replaced),
  );
}

void _diffMap(
  Map<dynamic, dynamic> a,
  Map<dynamic, dynamic> b,
  String basePath,
  List<AddedChange> added,
  List<RemovedChange> removed,
  List<ReplacedChange> replaced,
) {
  for (final key in {...a.keys, ...b.keys}) {
    final path = '$basePath/$key';
    final inA = a.containsKey(key);
    final inB = b.containsKey(key);
    if (!inA) {
      _walkAdds(b[key], path, added);
    } else if (!inB) {
      _walkRemoves(a[key], path, removed);
    } else {
      _diffValue(a[key], b[key], path, added, removed, replaced);
    }
  }
}

void _diffValue(
  dynamic before,
  dynamic after,
  String path,
  List<AddedChange> added,
  List<RemovedChange> removed,
  List<ReplacedChange> replaced,
) {
  if (before is Map && after is Map) {
    _diffMap(before, after, path, added, removed, replaced);
    return;
  }
  if (before is List && after is List) {
    final maxLen = before.length > after.length ? before.length : after.length;
    for (var i = 0; i < maxLen; i++) {
      final childPath = '$path/$i';
      if (i >= before.length) {
        _walkAdds(after[i], childPath, added);
      } else if (i >= after.length) {
        _walkRemoves(before[i], childPath, removed);
      } else {
        _diffValue(before[i], after[i], childPath, added, removed, replaced);
      }
    }
    return;
  }
  if (before != after) {
    replaced.add(ReplacedChange(path, before, after));
  }
}

/// Recursively emit one [AddedChange] per leaf inside [value]. Empty
/// maps and lists surface as a single change at [path] so the user
/// still sees that something appeared, just empty.
void _walkAdds(dynamic value, String path, List<AddedChange> out) {
  if (value is Map) {
    if (value.isEmpty) {
      out.add(AddedChange(path, value));
      return;
    }
    for (final entry in value.entries) {
      _walkAdds(entry.value, '$path/${entry.key}', out);
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      out.add(AddedChange(path, value));
      return;
    }
    for (var i = 0; i < value.length; i++) {
      _walkAdds(value[i], '$path/$i', out);
    }
    return;
  }
  out.add(AddedChange(path, value));
}

/// Mirror of [_walkAdds] for removals.
void _walkRemoves(dynamic value, String path, List<RemovedChange> out) {
  if (value is Map) {
    if (value.isEmpty) {
      out.add(RemovedChange(path, value));
      return;
    }
    for (final entry in value.entries) {
      _walkRemoves(entry.value, '$path/${entry.key}', out);
    }
    return;
  }
  if (value is List) {
    if (value.isEmpty) {
      out.add(RemovedChange(path, value));
      return;
    }
    for (var i = 0; i < value.length; i++) {
      _walkRemoves(value[i], '$path/$i', out);
    }
    return;
  }
  out.add(RemovedChange(path, value));
}
