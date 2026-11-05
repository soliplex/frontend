import 'upload_tracker.dart';

/// What a file list can be ordered by.
enum FileSortKey { folders, name, modified, size }

/// Every order a file list can take. Stored by [name], so renaming a value
/// resets that stored choice to the default.
enum FileSort {
  foldersAToZ(
    FileSortKey.folders,
    'Folders, A to Z: workspace files grouped by folder; uploads by name',
    descending: false,
  ),
  foldersZToA(
    FileSortKey.folders,
    'Folders, Z to A: workspace files grouped by folder; uploads by name',
    descending: true,
  ),
  nameAToZ(FileSortKey.name, 'Name, A to Z', descending: false),
  nameZToA(FileSortKey.name, 'Name, Z to A', descending: true),
  newestFirst(FileSortKey.modified, 'Modified, newest first', descending: true),
  oldestFirst(
    FileSortKey.modified,
    'Modified, oldest first',
    descending: false,
  ),
  largestFirst(FileSortKey.size, 'Size, largest first', descending: true),
  smallestFirst(FileSortKey.size, 'Size, smallest first', descending: false);

  const FileSort(this.key, this.description, {required this.descending});

  final FileSortKey key;

  /// Z to A, newest first, or largest first.
  final bool descending;

  /// The tooltip and semantics label of this order.
  final String description;

  /// The order a first tap on [key] selects: A to Z, newest first, or
  /// largest first.
  static FileSort firstTap(FileSortKey key) => switch (key) {
        FileSortKey.folders => foldersAToZ,
        FileSortKey.name => nameAToZ,
        FileSortKey.modified => newestFirst,
        FileSortKey.size => largestFirst,
      };

  /// The other order of the same [key].
  FileSort get reversed => switch (this) {
        foldersAToZ => foldersZToA,
        foldersZToA => foldersAToZ,
        nameAToZ => nameZToA,
        nameZToA => nameAToZ,
        newestFirst => oldestFirst,
        oldestFirst => newestFirst,
        largestFirst => smallestFirst,
        smallestFirst => largestFirst,
      };

  /// The order after a tap on [tapped]: the active key reverses; any other
  /// key gives [firstTap].
  FileSort tap(FileSortKey tapped) =>
      tapped == key ? reversed : firstTap(tapped);
}

/// [entries] in [sort]'s order. Under modified or size, an entry missing the
/// value comes after those that have it. Then the key, in [sort]'s direction:
/// folders and name compare the last segment of [path], ignoring case. Ties
/// go by [path] ascending. Only the key reverses with the direction.
List<T> sortFiles<T>(
  Iterable<T> entries,
  FileSort sort, {
  required String Function(T) path,
  required DateTime? Function(T) modifiedAt,
  required int? Function(T) sizeBytes,
}) {
  Comparable<Object>? keyOf(T entry) => switch (sort.key) {
        FileSortKey.folders || FileSortKey.name => _fileName(path(entry)),
        FileSortKey.modified => modifiedAt(entry),
        FileSortKey.size => sizeBytes(entry),
      };

  int compare(T a, T b) {
    final keyA = keyOf(a);
    final keyB = keyOf(b);
    if (keyA != null && keyB != null) {
      final byKey = keyA.compareTo(keyB);
      if (byKey != 0) return sort.descending ? -byKey : byKey;
    } else if (keyA != null || keyB != null) {
      return keyA == null ? 1 : -1;
    }
    return path(a).compareTo(path(b));
  }

  return entries.toList()..sort(compare);
}

/// The last segment of [path], lower-cased for comparison.
String _fileName(String path) =>
    path.substring(path.lastIndexOf('/') + 1).toLowerCase();

/// Pending and failed rows first, in their given order: they are the newest
/// activity. Then persisted rows by [sortFiles].
List<DisplayUpload> orderUploads(List<DisplayUpload> uploads, FileSort sort) =>
    [
      ...uploads.where((u) => u is! PersistedUpload),
      ...sortFiles<PersistedUpload>(
        uploads.whereType<PersistedUpload>(),
        sort,
        path: (u) => u.filename,
        modifiedAt: (u) => u.modifiedAt,
        sizeBytes: (u) => u.sizeBytes,
      ),
    ];

/// The order a place renders: [stored], or [FileSort.nameAToZ] when
/// [stored]'s key is modified and no entry there has a time ([hasTimes]
/// false), or size and none has a size ([hasSizes] false).
FileSort effectiveSort(
  FileSort stored, {
  required bool hasTimes,
  required bool hasSizes,
}) =>
    switch (stored.key) {
      FileSortKey.modified when !hasTimes => FileSort.nameAToZ,
      FileSortKey.size when !hasSizes => FileSort.nameAToZ,
      _ => stored,
    };
