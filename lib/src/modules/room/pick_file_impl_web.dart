import 'dart:async' show Completer;
import 'dart:js_interop';

import 'package:mime/mime.dart';
import 'package:web/web.dart' as web;

import 'pick_file.dart';

/// Web implementation of [pickFiles].
///
/// Uses a transient `<input type="file" multiple>` element rather than
/// `file_picker` so each picked file's bytes can be re-streamed on
/// demand via `Blob.stream()`. The browser yields a fresh
/// `ReadableStream<Uint8Array>` on every `file.stream()` call, which is
/// what makes the upload pipeline's auth-retry loop work on web without
/// holding a buffered `Uint8List` between attempts.
Future<PickFilesResult?> pickFilesImpl() async {
  final files = await _pickViaInput(folder: false);
  if (files == null) return null;
  return _toPickFilesResult(files, folderPick: false);
}

/// Web implementation of [pickFolder].
///
/// Adds the `webkitdirectory` attribute to the `<input>` element. The
/// browser then exposes each file's `webkitRelativePath` (e.g.
/// `myproject/src/main.dart`), which we mangle via
/// [mangleRelativePath] using the first segment as the root name.
Future<PickFilesResult?> pickFolderImpl() async {
  final files = await _pickViaInput(folder: true);
  if (files == null) return null;
  return _toPickFilesResult(files, folderPick: true);
}

Future<List<web.File>?> _pickViaInput({required bool folder}) {
  final input = web.document.createElement('input') as web.HTMLInputElement
    ..type = 'file'
    ..multiple = true;
  if (folder) input.webkitdirectory = true;

  final completer = Completer<List<web.File>?>();

  void completeWithFiles() {
    if (completer.isCompleted) return;
    final list = input.files;
    if (list == null || list.length == 0) {
      completer.complete(null);
      return;
    }
    final result = <web.File>[];
    for (var i = 0; i < list.length; i++) {
      final file = list.item(i);
      if (file != null) result.add(file);
    }
    completer.complete(result);
  }

  input.onchange = ((web.Event _) => completeWithFiles()).toJS;
  // 'cancel' is the modern way browsers signal a closed file dialog
  // with no selection. Supported in Chrome 113+, Firefox 91+, Safari
  // 16.4+. Older browsers leave the future pending — accepted limit.
  input.oncancel = ((web.Event _) {
    if (!completer.isCompleted) completer.complete(null);
  }).toJS;

  input.click();
  return completer.future;
}

PickFilesResult _toPickFilesResult(
  List<web.File> webFiles, {
  required bool folderPick,
}) {
  final files = <PickedFile>[];
  final errors = <PickFileItemError>[];

  for (final webFile in webFiles) {
    final originalName = webFile.name;

    final String pickedName;
    if (folderPick) {
      final relative = webFile.webkitRelativePath;
      if (relative.isEmpty) continue;
      final segments = relative.split('/');
      if (segments.any((s) => s.startsWith('.'))) continue;
      final rootName = segments.first;
      final tail = segments.skip(1).join('/');
      try {
        pickedName = mangleRelativePath(rootName, tail);
      } on FormatException catch (e) {
        errors.add(PickFileItemError(filename: relative, cause: e));
        continue;
      }
    } else {
      pickedName = originalName;
    }

    final mimeType = lookupMimeType(pickedName) ?? 'application/octet-stream';

    files.add(
      PickedFile(
        name: pickedName,
        mimeType: mimeType,
        size: webFile.size,
        openStream: () => _blobStream(webFile),
      ),
    );
  }

  return (files: files, errors: errors);
}

/// Reads a [web.Blob] (or any subclass like [web.File]) as a stream of
/// `Uint8List` chunks by adapting its underlying
/// `ReadableStream<Uint8Array>`. The blob isn't consumed until the
/// stream is listened to, and a fresh `ReadableStream` is created on
/// every call — the upload pipeline relies on this for retries.
Stream<List<int>> _blobStream(web.Blob blob) async* {
  final reader = web.ReadableStreamDefaultReader(blob.stream());
  try {
    while (true) {
      final result = await reader.read().toDart;
      if (result.done) break;
      final value = result.value;
      if (value == null) continue;
      yield (value as JSUint8Array).toDart;
    }
  } finally {
    // Release the lock so subsequent calls can create a new reader if
    // the same blob is re-streamed.
    reader.releaseLock();
  }
}
