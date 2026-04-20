import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:soliplex_logging/src/sinks/disk_queue.dart';

/// Maximum queue file size before compaction (10 MB).
const int _maxFileBytes = 10 * 1024 * 1024;

/// Number of confirmed records before triggering compaction.
const int _compactThreshold = 500;

/// Sentinel value meaning `_total` has not been computed yet.
const int _unknownTotal = -1;

/// Native (io) implementation of [DiskQueue] using JSONL files.
///
/// Uses an offset-based architecture: the main file is append-only,
/// a small metadata file tracks how many records have been confirmed,
/// and compaction (the only file rewrite) runs rarely.
class PlatformDiskQueue implements DiskQueue {
  /// Creates a disk queue that stores records in [directoryPath].
  PlatformDiskQueue({required String directoryPath})
    : _directory = Directory(directoryPath) {
    _directory.createSync(recursive: true);
    _file = File('${_directory.path}/log_queue.jsonl');
    _fatalFile = File('${_directory.path}/log_queue_fatal.jsonl');
    _metaFile = File('${_directory.path}/.queue_meta');
    _migrateIfNeeded();
    _loadMeta();
  }

  final Directory _directory;
  late final File _file;
  late final File _fatalFile;
  late final File _metaFile;

  /// Number of confirmed (consumed) records at the head of the file.
  int _confirmed = 0;

  /// Total number of valid records in the file. -1 means unknown.
  int _total = _unknownTotal;

  /// Serializes async writes to prevent file corruption.
  Future<void> _writeLock = Future.value();

  @override
  Future<void> append(Map<String, Object?> json) {
    final completer = Completer<void>();
    _writeLock = _writeLock.catchError((_) {}).then((_) async {
      try {
        await _compactIfNeeded();
        final line = '${jsonEncode(json)}\n';
        await _file.writeAsString(line, mode: FileMode.append, flush: true);
        if (_total != _unknownTotal) _total++;
        completer.complete();
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  @override
  void appendSync(Map<String, Object?> json) {
    final line = '${jsonEncode(json)}\n';
    _fatalFile.writeAsStringSync(line, mode: FileMode.append, flush: true);
  }

  @override
  Future<List<Map<String, Object?>>> drain(int count) {
    final completer = Completer<List<Map<String, Object?>>>();
    _writeLock = _writeLock.catchError((_) {}).then((_) async {
      try {
        completer.complete(await _drainUnsafe(count));
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  Future<List<Map<String, Object?>>> _drainUnsafe(int count) async {
    await _mergeFatalFile();
    if (!_file.existsSync()) return const [];

    await _ensureTotal();

    final results = <Map<String, Object?>>[];
    var validSeen = 0;

    await for (final line in _readLinesStream()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, Object?>) {
          validSeen++;
          if (validSeen <= _confirmed) continue; // skip confirmed
          results.add(decoded);
          if (results.length >= count) break;
        }
      } on FormatException {
        // Skip corrupted lines.
      }
    }

    return results;
  }

  @override
  Future<void> confirm(int count) {
    final completer = Completer<void>();
    _writeLock = _writeLock.catchError((_) {}).then((_) async {
      try {
        _confirmed += count;
        if (_total != _unknownTotal && _confirmed > _total) {
          _confirmed = _total;
        }
        _writeMeta();
        completer.complete();
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  @override
  Future<int> get pendingCount {
    final completer = Completer<int>();
    _writeLock = _writeLock.catchError((_) {}).then((_) async {
      try {
        await _mergeFatalFile();
        await _ensureTotal();
        final pending = _total - _confirmed;
        completer.complete(pending < 0 ? 0 : pending);
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  @override
  Future<void> clear() {
    final completer = Completer<void>();
    _writeLock = _writeLock.catchError((_) {}).then((_) async {
      try {
        if (_file.existsSync()) _file.deleteSync();
        if (_fatalFile.existsSync()) _fatalFile.deleteSync();
        _confirmed = 0;
        _total = 0;
        _writeMeta();
        completer.complete();
      } on Object catch (e, s) {
        completer.completeError(e, s);
      }
    });
    return completer.future;
  }

  @override
  Future<void> close() async {
    await _writeLock.catchError((_) {});
  }

  // ---------------------------------------------------------------------------
  // Fatal merge
  // ---------------------------------------------------------------------------

  /// Merges fatal file contents into the main queue file by direct append.
  ///
  /// Renames the fatal file before reading so that concurrent [appendSync]
  /// calls write to a fresh file and never race with the merge read.
  Future<void> _mergeFatalFile() async {
    if (!_fatalFile.existsSync()) return;

    // Rename to isolate from concurrent appendSync writes.
    final mergeFile = File('${_directory.path}/.fatal_processing.tmp');
    try {
      _fatalFile.renameSync(mergeFile.path);
    } on FileSystemException {
      return;
    }

    final content = mergeFile.readAsStringSync();
    if (content.trim().isEmpty) {
      mergeFile.deleteSync();
      return;
    }

    // Direct append — O(fatal_size), not O(file_size).
    await _file.writeAsString(content, mode: FileMode.append, flush: true);

    // Count valid records added.
    final added = _countValidRecords(content);
    if (_total != _unknownTotal) _total += added;

    mergeFile.deleteSync();
  }

  // ---------------------------------------------------------------------------
  // Compaction
  // ---------------------------------------------------------------------------

  /// Triggers compaction when confirmed count or file size is too large.
  Future<void> _compactIfNeeded() async {
    if (_confirmed >= _compactThreshold) {
      await _compact(_confirmed);
      return;
    }
    if (_file.existsSync() && _file.statSync().size > _maxFileBytes) {
      // Rotation: drop confirmed + half of pending.
      await _ensureTotal();
      final pending = _total - _confirmed;
      final toDrop = _confirmed + (pending > 0 ? pending ~/ 2 : 0);
      await _compact(toDrop);
    }
  }

  /// Drops the first [recordsToDrop] valid records from the file.
  ///
  /// Writes survivors to a temp file, atomically renames, then resets meta.
  Future<void> _compact(int recordsToDrop) async {
    if (!_file.existsSync()) return;

    final tmpFile = File('${_directory.path}/.log_queue_compact.tmp');
    final sink = tmpFile.openWrite();
    var dropped = 0;
    var kept = 0;

    await for (final line in _readLinesStream()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, Object?>) {
          if (dropped < recordsToDrop) {
            dropped++;
            continue;
          }
          sink.writeln(trimmed);
          kept++;
        }
        // Non-Map JSON — discard silently.
      } on FormatException {
        // Corrupted line — discard silently.
      }
    }

    await sink.close();

    // Write meta BEFORE rename: if we crash between meta write and rename,
    // we get duplicate records on restart (at-least-once) instead of data loss.
    _confirmed = 0;
    _total = kept;
    _writeMeta();

    await tmpFile.rename(_file.path);
  }

  // ---------------------------------------------------------------------------
  // Meta file
  // ---------------------------------------------------------------------------

  /// Loads confirmed count from `.queue_meta`. Defaults to 0 on error.
  void _loadMeta() {
    if (!_metaFile.existsSync()) return;
    try {
      final content = _metaFile.readAsStringSync();
      final decoded = jsonDecode(content);
      if (decoded is Map<String, Object?>) {
        final c = decoded['confirmed'];
        if (c is int && c >= 0) _confirmed = c;
      }
    } on Object {
      // Corrupt meta — treat all records as unconfirmed.
      _confirmed = 0;
    }
  }

  /// Persists confirmed count to `.queue_meta`.
  void _writeMeta() {
    _metaFile.writeAsStringSync(
      jsonEncode({'confirmed': _confirmed}),
      flush: true,
    );
  }

  // ---------------------------------------------------------------------------
  // Total tracking
  // ---------------------------------------------------------------------------

  /// Ensures `_total` is computed. Clamps `_confirmed` if needed.
  Future<void> _ensureTotal() async {
    if (_total != _unknownTotal) return;
    if (!_file.existsSync()) {
      _total = 0;
      if (_confirmed > 0) {
        _confirmed = 0;
        _writeMeta();
      }
      return;
    }

    var count = 0;
    await for (final line in _readLinesStream()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, Object?>) count++;
      } on FormatException {
        // skip
      }
    }

    _total = count;
    if (_confirmed > _total) {
      _confirmed = _total;
      _writeMeta();
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Streams lines from the queue file without loading it all into memory.
  Stream<String> _readLinesStream() {
    return _file
        .openRead()
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter());
  }

  /// Counts valid Map records in a string of JSONL content.
  int _countValidRecords(String content) {
    var count = 0;
    for (final line in const LineSplitter().convert(content)) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, Object?>) count++;
      } on FormatException {
        // skip
      }
    }
    return count;
  }

  /// Recovers orphaned fatal processing file and deletes old temp files.
  void _migrateIfNeeded() {
    // Recover orphaned fatal processing file from a crash during merge.
    final orphanedMerge = File('${_directory.path}/.fatal_processing.tmp');
    if (orphanedMerge.existsSync()) {
      final content = orphanedMerge.readAsStringSync();
      if (content.trim().isNotEmpty) {
        _file.writeAsStringSync(content, mode: FileMode.append, flush: true);
      }
      orphanedMerge.deleteSync();
    }

    // Delete old temp files from previous implementations.
    for (final name in [
      '.log_queue_merge.tmp',
      '.log_queue_confirm.tmp',
      '.log_queue_rotate.tmp',
      '.fatal_merge.jsonl',
    ]) {
      final f = File('${_directory.path}/$name');
      if (f.existsSync()) f.deleteSync();
    }
  }
}
