import 'dart:io';

import 'package:flutter/material.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/failed_image.dart';

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
        _logger.warning(
          'file image failed to load: $rawUri',
          error: error,
          stackTrace: stack,
        );
        return FailedImage(source: rawUri, label: alt);
      },
    );
  } on UnsupportedError catch (error, stack) {
    _logger.warning(
      'file: URI could not be converted to a file path: $rawUri',
      error: error,
      stackTrace: stack,
    );
    return FailedImage(source: rawUri, label: alt);
  }
}
