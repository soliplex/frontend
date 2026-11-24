import 'dart:async';

import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show ServedFile;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../shared/download_feedback.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.downloads');

/// Each file's download from one `FileSource`: idle, under way, then its
/// outcome. A save shows for 2 s before the file is idle again; a failure
/// shows until a retry starts or these downloads are cleared, so its reason
/// stays to read. A save the user cancels goes straight back to idle.
///
/// Every affordance that downloads a file reads its state here and starts it
/// here, so a file row, the preview and the PDF viewer show one download,
/// and a file starts no second one while one runs or its save shows.
class FileDownloads {
  FileDownloads(this._download);

  /// Downloads a file; must report routine failures as [DownloadFailed]
  /// rather than throw. Its `isCleared` says whether these downloads were
  /// cleared since, so nobody is left to want the file.
  final Future<DownloadOutcome> Function(
    ServedFile file,
    bool Function() isCleared,
  ) _download;

  /// The files not idle, by path, so a file absent from it is idle. A path,
  /// not the listed [ServedFile], so a refresh that reports the file with a
  /// new modified time or size leaves its download in place.
  final _states = Signal<Map<String, DownloadFeedbackState>>(const {});
  final _outcomeTimers = <String, Timer>{};
  bool _isDisposed = false;

  /// [file]'s state; read inside a `Watch`, it rebuilds when any file's
  /// download changes. Each failed attempt reads as a [DownloadFailed] of
  /// its own.
  DownloadFeedbackState stateOf(ServedFile file) =>
      _states.value[file.filename] ?? const DownloadIdle();

  /// Whether [start] would download [file]: it is idle, or its download
  /// failed, which a new one retries. Read inside a `Watch`, it rebuilds as
  /// [stateOf] does.
  bool canStart(ServedFile file) => stateOf(file).canStart;

  /// Downloads [file], unless its download runs or its save shows.
  /// Starts nothing once disposed, when nobody is left to want the file.
  Future<void> start(ServedFile file) async {
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
        'file download threw',
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
      // A new instance per attempt, even when the download returned a const
      // one: the PDF viewer hides a dismissed failure by identity, so a
      // reused instance would hide the next failure too.
      case DownloadFailed(:final reason):
        _set(path, DownloadFailed(reason));
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
