import 'dart:io';

import 'package:flutter/material.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/failed_image.dart';
import 'log_source.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.markdown_image');

/// Native implementation of [loadFileImage] for platforms with `dart:io`.
/// `File.fromUri(uri)` calls `uri.toFilePath()`, which throws
/// [UnsupportedError] for `file:` URIs with a non-localhost authority on
/// non-Windows systems, a fragment, a query string, or certain Windows
/// drive-letter cases. Such construction failures route to [FailedImage],
/// as do async load failures via the [Image.file] `errorBuilder`.
Widget loadFileImage(Uri uri, String rawUri, String? alt) {
  try {
    return Image.file(
      File.fromUri(uri),
      errorBuilder: (_, error, stack) {
        logFailedSourceOnce(
          _logger,
          'file image failed to load: ${safeSourceForLog(rawUri)}',
          rawUri,
          error: error,
          stackTrace: stack,
        );
        return FailedImage(source: rawUri, label: alt);
      },
    );
  } on UnsupportedError catch (error, stack) {
    logFailedSourceOnce(
      _logger,
      'file: URI could not be converted to a file path: '
      '${safeSourceForLog(rawUri)}',
      rawUri,
      error: error,
      stackTrace: stack,
    );
    return FailedImage(source: rawUri, label: alt);
  }
}
