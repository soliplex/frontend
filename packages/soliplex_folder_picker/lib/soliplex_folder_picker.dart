/// Picks a folder through the platform's own document picker and reads its
/// files by the reference that picker grants.
///
/// It exists for the platforms where a picked folder's path cannot be read
/// with `dart:io`. On Android the picker grants a document tree, and scoped
/// storage hides the files under the path a tree resolves to.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One file found under a picked folder.
@immutable
class FolderEntry {
  /// Creates an entry.
  const FolderEntry({
    required this.relativePath,
    required this.uri,
    required this.size,
  });

  /// The file's path below the picked folder, its segments joined with `/`.
  final String relativePath;

  /// The platform's reference to the file, which
  /// [SoliplexFolderPicker.openRead] takes. Opaque: on Android a `content://`
  /// document URI.
  final String uri;

  /// The file's length in bytes, or `null` when the platform does not say.
  final int? size;
}

/// A folder the user picked, with every file below it.
@immutable
class PickedFolder {
  /// Creates a picked folder.
  const PickedFolder({required this.name, required this.files});

  /// The folder's display name.
  final String name;

  /// Every file below the folder, at any depth. Folders are not listed.
  final List<FolderEntry> files;
}

/// The folder picker.
///
/// The native side answers four methods on [channelName]. This is the whole
/// contract a platform implements:
///
/// - `pick`, no arguments: `null` on cancel, or
///   `{name, files: [{path, uri, size}]}`. `path` joins segments with `/`;
///   `size` may be `null`.
/// - `open`, `{uri}`: an `int` handle.
/// - `read`, `{handle, max}`: up to `max` bytes, or `null` at the end.
/// - `close`, `{handle}`: `null`.
///
/// A failure answers a `PlatformException`, whose message names the file and
/// the reason.
class SoliplexFolderPicker {
  /// Creates a picker over [channel], for [platform] (the running one by
  /// default).
  SoliplexFolderPicker({
    @visibleForTesting MethodChannel? channel,
    @visibleForTesting TargetPlatform? platform,
    @visibleForTesting bool? isWeb,
  })  : _channel = channel ?? const MethodChannel(channelName),
        _platform = platform ?? defaultTargetPlatform,
        _isWeb = isWeb ?? kIsWeb;

  /// The method channel's name.
  static const channelName = 'ai.soliplex/folder_picker';

  /// The platforms with a native side. A platform is added here together
  /// with its implementation and its entry in the pubspec.
  static const supportedPlatforms = {TargetPlatform.android};

  /// The size of each read, in bytes.
  static const chunkSize = 256 * 1024;

  final MethodChannel _channel;
  final TargetPlatform _platform;
  final bool _isWeb;

  /// Whether this platform has a native side. Callers use their own picker
  /// where it has not.
  bool get isSupported => !_isWeb && supportedPlatforms.contains(_platform);

  /// Opens the folder picker and lists every file below the chosen folder.
  ///
  /// Answers `null` when the user cancels.
  Future<PickedFolder?> pick() async {
    final answer = await _channel.invokeMapMethod<String, Object?>('pick');
    if (answer == null) return null;
    final files = (answer['files']! as List<Object?>).map((raw) {
      final file = (raw! as Map<Object?, Object?>).cast<String, Object?>();
      return FolderEntry(
        relativePath: file['path']! as String,
        uri: file['uri']! as String,
        size: file['size'] as int?,
      );
    }).toList();
    return PickedFolder(name: answer['name']! as String, files: files);
  }

  /// Reads the file at [uri], a [FolderEntry.uri], in chunks of [chunkSize].
  ///
  /// Each call opens the file afresh, so a retried upload can read it again.
  /// The file is closed when the stream ends, fails or is cancelled.
  Stream<List<int>> openRead(String uri) async* {
    final handle = await _channel.invokeMethod<int>('open', {'uri': uri});
    try {
      while (true) {
        final chunk = await _channel.invokeMethod<Uint8List>(
          'read',
          {'handle': handle, 'max': chunkSize},
        );
        if (chunk == null) return;
        yield chunk;
      }
    } finally {
      await _channel.invokeMethod<void>('close', {'handle': handle});
    }
  }
}
