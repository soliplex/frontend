import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart';
import 'package:soliplex_client/soliplex_client.dart' show ServedFile;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../core/ui/confirm_dialog.dart';
import '../../../shared/file_size.dart';
import '../file_downloads.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.downloads');

/// Above this listed size, a download on mobile or the web asks first. A
/// download holds the whole file in memory before it is saved, and those
/// platforms end an app or a tab that uses too much. Downloading a large file
/// without that risk needs the download streamed to disk instead.
const largeDownloadWarningBytes = 100 * 1024 * 1024;

/// Whether a download of a file listed at [sizeBytes] asks first on
/// [platform], or on the web when [isWeb].
bool warnsBeforeDownload(
  int sizeBytes, {
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (sizeBytes <= largeDownloadWarningBytes) return false;
  if (isWeb) return true;
  return switch (platform) {
    TargetPlatform.iOS || TargetPlatform.android => true,
    TargetPlatform.macOS ||
    TargetPlatform.windows ||
    TargetPlatform.linux ||
    TargetPlatform.fuchsia =>
      false,
  };
}

/// Starts [file]'s download in [downloads], once the user confirms when
/// [warnsBeforeDownload] says one this size could exhaust this device's
/// memory. A file with no listed size starts without asking: nothing says it
/// is large.
Future<void> startDownload(
  BuildContext context,
  FileDownloads downloads,
  ServedFile file,
) async {
  if (file.sizeBytes case final size?
      when warnsBeforeDownload(
        size,
        isWeb: kIsWeb,
        platform: defaultTargetPlatform,
      )) {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Download ${file.basename}?',
      message: "If this device doesn't have enough memory for this download "
          '(${formatFileSize(size)}), the app could close before the file is '
          'saved.',
      confirmLabel: 'Download',
    );
    if (!confirmed) {
      _logger.debug(
        'large download declined',
        attributes: {'filename': file.filename, 'sizeBytes': size},
      );
      return;
    }
  }
  await downloads.start(file);
}
