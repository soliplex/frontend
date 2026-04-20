import 'dart:async' show unawaited;

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';

/// Upload status for a single file.
sealed class UploadStatus {
  const UploadStatus();
  static const uploading = UploadUploading();
  static const success = UploadSuccess();
}

class UploadUploading extends UploadStatus {
  const UploadUploading();
}

class UploadSuccess extends UploadStatus {
  const UploadSuccess();
}

class UploadError extends UploadStatus {
  const UploadError(this.message);
  final String message;
}

/// A single tracked upload.
class UploadEntry {
  UploadEntry({
    required this.id,
    required this.filename,
    required this.status,
    required this.scope,
  });

  final String id;
  final String filename;
  final UploadStatus status;

  /// The scope key this entry belongs to (room or room+thread).
  final String scope;

  UploadEntry _withStatus(UploadStatus newStatus) =>
      UploadEntry(id: id, filename: filename, status: newStatus, scope: scope);
}

/// Tracks file upload state across rooms and threads.
///
/// Each upload is fire-and-forget: it starts immediately and transitions
/// through uploading → success/error. The tracker exposes signals per
/// scope so the UI can react.
///
/// This only tracks uploads initiated in this session. There is no
/// backend endpoint to list previously uploaded files.
// TODO(backend): Add GET /v1/uploads/{room_id} and
// GET /v1/uploads/{room_id}/{thread_id} endpoints to list uploaded files,
// then replace session-only tracking with server-fetched lists.
class UploadTracker {
  final Map<String, Signal<List<UploadEntry>>> _scopes = {};
  int _nextId = 0;
  bool _disposed = false;

  Signal<List<UploadEntry>> _scopeSignal(String key) =>
      _scopes.putIfAbsent(key, () => Signal<List<UploadEntry>>([]));

  static String _roomKey(String roomId) => 'room:$roomId';

  static String _threadKey(String roomId, String threadId) =>
      'thread:$roomId:$threadId';

  /// Signal of uploads for a room scope.
  ReadonlySignal<List<UploadEntry>> roomUploads(String roomId) =>
      _scopeSignal(_roomKey(roomId));

  /// Signal of uploads for a thread scope.
  ReadonlySignal<List<UploadEntry>> threadUploads(
    String roomId,
    String threadId,
  ) => _scopeSignal(_threadKey(roomId, threadId));

  /// Starts a room-level upload.
  void uploadToRoom({
    required SoliplexApi api,
    required String roomId,
    required String filename,
    required List<int> fileBytes,
    String mimeType = 'application/octet-stream',
  }) {
    final key = _roomKey(roomId);
    final entry = _addEntry(key, filename);
    unawaited(
      api
          .uploadFileToRoom(
            roomId,
            filename: filename,
            fileBytes: fileBytes,
            mimeType: mimeType,
          )
          .then((_) => _updateStatus(key, entry.id, UploadStatus.success))
          .catchError((Object error) {
            _updateStatus(key, entry.id, UploadError(_errorMessage(error)));
          }),
    );
  }

  /// Starts a thread-level upload.
  void uploadToThread({
    required SoliplexApi api,
    required String roomId,
    required String threadId,
    required String filename,
    required List<int> fileBytes,
    String mimeType = 'application/octet-stream',
  }) {
    final key = _threadKey(roomId, threadId);
    final entry = _addEntry(key, filename);
    unawaited(
      api
          .uploadFileToThread(
            roomId,
            threadId,
            filename: filename,
            fileBytes: fileBytes,
            mimeType: mimeType,
          )
          .then((_) => _updateStatus(key, entry.id, UploadStatus.success))
          .catchError((Object error) {
            _updateStatus(key, entry.id, UploadError(_errorMessage(error)));
          }),
    );
  }

  /// Removes an entry (e.g., user dismisses an error or completed upload).
  void dismiss(String entryId) {
    for (final signal in _scopes.values) {
      final list = signal.value;
      final index = list.indexWhere((e) => e.id == entryId);
      if (index >= 0) {
        signal.value = [...list]..removeAt(index);
        return;
      }
    }
  }

  UploadEntry _addEntry(String scopeKey, String filename) {
    final id = 'upload-${_nextId++}';
    final entry = UploadEntry(
      id: id,
      filename: filename,
      status: UploadStatus.uploading,
      scope: scopeKey,
    );
    final signal = _scopeSignal(scopeKey);
    signal.value = [...signal.value, entry];
    return entry;
  }

  void _updateStatus(String scopeKey, String entryId, UploadStatus status) {
    if (_disposed) return;
    final signal = _scopes[scopeKey];
    if (signal == null) return;
    signal.value = [
      for (final e in signal.value)
        if (e.id == entryId) e._withStatus(status) else e,
    ];
  }

  static String _errorMessage(Object error) {
    if (error is SoliplexException) return error.message;
    return error.toString();
  }

  void dispose() {
    _disposed = true;
    for (final signal in _scopes.values) {
      signal.dispose();
    }
    _scopes.clear();
  }
}
