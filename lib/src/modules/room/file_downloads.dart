import 'dart:async';

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_logging/soliplex_logging.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.downloads');

/// Result of a workdir-file download attempt.
sealed class DownloadOutcome {}

/// Where a file's download stands in [FileDownloads]. An outcome that
/// shows, [DownloadSaved] or [DownloadFailed], is a state as it is.
sealed class DownloadFeedbackState {}

/// No download runs, and no outcome shows.
final class DownloadIdle implements DownloadFeedbackState {
  const DownloadIdle();
}

final class DownloadRunning implements DownloadFeedbackState {
  const DownloadRunning();
}

/// The file was saved, or on the web handed to the browser.
final class DownloadSaved implements DownloadOutcome, DownloadFeedbackState {
  const DownloadSaved();
}

/// Nothing was saved and nothing failed: the user cancelled the save, or
/// nobody was left to want the file. Kept apart from [DownloadFailed] so
/// the UI shows no error for it.
final class DownloadCancelled implements DownloadOutcome {
  const DownloadCancelled();
}

final class DownloadFailed implements DownloadOutcome, DownloadFeedbackState {
  const DownloadFailed(this.reason);

  /// Why, in words for the user: fixed text, never the error's own.
  final String reason;
}

/// Each file's download in one thread's workspace: idle, under way, then its
/// outcome. A save shows for 2 s before the file is idle again; a failure
/// shows until the file is downloaded again, so its reason stays to read. A
/// save the user cancels goes straight back to idle.
///
/// Every affordance that downloads a file reads its state here and starts it
/// here, so a file row and the preview show one download, and a file starts
/// no second one while one runs or its save shows.
class FileDownloads {
  FileDownloads(this._download);

  /// Downloads a file; must report routine failures as [DownloadFailed]
  /// rather than throw. Its `isCleared` says whether
  /// these downloads were cleared since, so nobody is left to want the file.
  final Future<DownloadOutcome> Function(
    WorkdirFile file,
    bool Function() isCleared,
  ) _download;

  /// The files not idle, by path, so a file absent from it is idle. A path,
  /// not the listed [WorkdirFile], so a refresh that reports the file with a
  /// new modified time or size leaves its download in place.
  final _states = Signal<Map<String, DownloadFeedbackState>>(const {});
  final _outcomeTimers = <String, Timer>{};
  bool _isDisposed = false;

  /// [file]'s state; read inside a `Watch`, it rebuilds when any file's
  /// download changes.
  DownloadFeedbackState stateOf(WorkdirFile file) =>
      _states.value[file.filename] ?? const DownloadIdle();

  /// Whether [start] would download [file]: it is idle, or its download
  /// failed, which a new one retries. Read inside a `Watch`, it rebuilds as
  /// [stateOf] does.
  bool canStart(WorkdirFile file) => switch (stateOf(file)) {
        DownloadIdle() || DownloadFailed() => true,
        DownloadRunning() || DownloadSaved() => false,
      };

  /// Downloads [file], unless its download runs or its save shows.
  /// Starts nothing once disposed, when nobody is left to want the file.
  Future<void> start(WorkdirFile file) async {
    if (_isDisposed) {
      _logger.debug(
        'download not started, its downloads cleared',
        attributes: {'filename': file.filename},
      );
      return;
    }
    if (!canStart(file)) return;
    final path = file.filename;
    _set(path, const DownloadRunning());
    DownloadOutcome outcome;
    try {
      outcome = await _download(file, () => _isDisposed);
    } catch (e, st) {
      // A broken contract, so it may carry anything: its text stays out.
      _logger.error(
        'workdir download threw',
        stackTrace: st,
        attributes: {
          'filename': path,
          'failure': describeFailure(e),
        },
      );
      outcome = const DownloadFailed('Something went wrong');
    }
    // The outcome is logged; nothing is left to show it.
    if (_isDisposed) return;
    switch (outcome) {
      case DownloadCancelled():
        _set(path, const DownloadIdle());
      case DownloadSaved():
        _showSaved(path, outcome);
      case DownloadFailed():
        _set(path, outcome);
    }
  }

  void _showSaved(String path, DownloadSaved outcome) {
    _set(path, outcome);
    _outcomeTimers[path] = Timer(const Duration(seconds: 2), () {
      _outcomeTimers.remove(path);
      _set(path, const DownloadIdle());
    });
  }

  void _set(String path, DownloadFeedbackState state) {
    _states.value = state is DownloadIdle
        ? ({..._states.value}..remove(path))
        : {..._states.value, path: state};
  }

  /// Clears these downloads: every file reads idle and none starts again.
  /// The state stays readable, not disposed, as a screen that still shows
  /// these downloads may read it until it is rebuilt or goes away.
  void dispose() {
    _isDisposed = true;
    for (final timer in _outcomeTimers.values) {
      timer.cancel();
    }
    _states.value = const {};
  }
}
