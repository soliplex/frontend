import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show ServedFile;

import '../file_downloads.dart';
import 'file_list_row.dart';
import 'start_download.dart';
import '../../../shared/download_feedback.dart';

/// A file row's download action for [file]: its icon and tooltip follow the
/// file's download in [downloads], and a spinner takes its place while one
/// runs. A tap starts it through [startDownload], which may ask first.
class FileRowDownloadAction extends StatelessWidget {
  const FileRowDownloadAction({
    super.key,
    required this.file,
    required this.downloads,
  });

  final ServedFile file;
  final FileDownloads downloads;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Watch((context) {
      final state = downloads.stateOf(file);
      final (icon, tooltip) = state.affordance;
      if (state is DownloadRunning) {
        return FileRowActionProgress(label: tooltip);
      }
      return FileRowAction(
        icon: icon,
        tooltip: tooltip,
        onTap: downloads.canStart(file)
            ? () => unawaited(startDownload(context, downloads, file))
            : null,
        color: state.outcomeColor(colorScheme) ?? colorScheme.primary,
      );
    });
  }
}
