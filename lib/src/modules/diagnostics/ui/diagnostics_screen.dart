import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../core/routes.dart';
import '../../auth/ui/home_shell.dart';
import '../log_capture.dart';
import '../models/diagnostics_report.dart';
import '../models/http_event_grouper.dart';
import '../models/log_record_format.dart';
import '../network_inspector.dart';
import 'logs_pane.dart';
import 'requests_pane.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.diagnostics_screen');

/// Outcome of the last export, shown inline on the action rather than through
/// a transient message, and reverted on a timer — the same shape the shared
/// copy button uses.
enum _ExportFeedback {
  idle,
  savedToFile,

  /// Web has no save dialog and no way to observe the download it dispatched,
  /// so this claims only that one was started.
  downloadStarted,
  failed,
}

/// Which of the three ways an export can fail happened. They leave different
/// things behind, and telling the user the wrong one sends them looking for a
/// file that does not exist — or fails to warn them about one that does.
enum _ExportFailure {
  /// The report was never built, so nothing was offered to a dialog.
  reportNotBuilt,

  /// The dialog closed and the save then failed. On a desktop platform the
  /// bytes are written after it closes, so a truncated file may exist.
  saveFailed,

  /// The dialog never answered. Nothing has been written, and the user may
  /// still finish it — in which case the file appears normally.
  saveNeverAnswered,
}

/// [fileName] is the name the app *offered* the dialog, not necessarily the
/// file that exists: the dialog lets the user rename, and it returns the path
/// it actually used only on success.
///
/// [at] stamps the attempt, because the notice deliberately outlives the
/// attempt that raised it: without a time a standing notice reads as the
/// verdict on whatever the user did last.
typedef _ExportProblem = ({DateTime at, _ExportFailure kind, String? fileName});

/// Which capture the screen is showing. The two are bounded separately — the
/// inspector drops the oldest HTTP event past its cap, the sink overwrites the
/// oldest record past its own — and HTTP events churn far faster under
/// streaming traffic than records are written, so a failure recorded in the
/// log routinely outlives the request that caused it. (A host app that
/// configures its own MemorySink can change its capacity, which would change
/// that; the inspector's cap is fixed by the flavor.)
enum _View { requests, logs }

class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({
    required this.appName,
    required this.inspector,
    this.logo,
    this.initialRunId,
    super.key,
  });

  final String appName;
  final Widget? logo;
  final NetworkInspector inspector;

  /// When set (via the per-message deep link), the request list opens scoped to
  /// this agent run, shown as a removable chip.
  final String? initialRunId;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  _ExportFeedback _exportFeedback = _ExportFeedback.idle;
  Timer? _exportRevertTimer;
  _View _view = _View.requests;

  /// Guards against a second export starting while one is in flight, which on
  /// desktop would open two save dialogs over each other.
  bool _exporting = false;

  /// Set when a save failed, and kept until the next attempt that produces an
  /// outcome — a dismissed dialog leaves it standing on purpose, since it names
  /// a file the user may still have to go and inspect. Unlike the success
  /// glyphs it does not time out: it is the only account the user gets of an
  /// action that produced nothing, and a tooltip cannot be read on a touch
  /// screen.
  _ExportProblem? _exportProblem;

  /// Held here, not in [RequestsPane], because switching panes disposes that
  /// pane: a run filter the user dismissed would come back seeded from the
  /// deep link, silently re-hiding traffic.
  String? _runId;

  /// Resolved once. Re-reading [LogManager] on every build would leave the
  /// screen able to disagree with itself about which sink it is showing.
  late final MemorySink? _logSink;

  /// Whether the log capture holds anything. Drives the export and clear
  /// actions in the header; [LogsPane] owns rendering the records themselves,
  /// and the export reads them from [_logSink] when it runs.
  bool _hasLogRecords = false;
  final List<StreamSubscription<void>> _logSubscriptions = [];

  @override
  void initState() {
    super.initState();
    _runId = widget.initialRunId;
    _logSink = capturedLogSink(LogManager.instance);
    final sink = _logSink;
    if (sink != null) {
      _hasLogRecords = sink.length > 0;
      // Only the empty/non-empty transition matters here, so a busy debug
      // session does not rebuild the screen once per record. The pane
      // subscribes separately for the rows.
      _logSubscriptions.addAll([
        sink.onRecord.listen((_) => _setHasLogRecords(true)),
        sink.onClear.listen((_) => _setHasLogRecords(false)),
      ]);
    }
  }

  @override
  void dispose() {
    _exportRevertTimer?.cancel();
    for (final subscription in _logSubscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  void _setHasLogRecords(bool value) {
    if (!mounted || _hasLogRecords == value) return;
    setState(() => _hasLogRecords = value);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.inspector,
      builder: (context, _) {
        final hasRequests = widget.inspector.events.isNotEmpty;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                HomeShellHeader(
                  appName: widget.appName,
                  logo: widget.logo,
                  showUtilityMenu: false,
                  leading: IconButton(
                    icon: Icon(Icons.adaptive.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => context.canPop()
                        ? context.pop()
                        : context.go(AppRoutes.lobby),
                  ),
                  actions: [
                    IconButton(
                      icon: Icon(
                        _exportAffordance.icon,
                        color: _exportAffordance.color,
                      ),
                      // Disabled while one is in flight, so the control stops
                      // claiming to be available during a save that can take
                      // as long as the user takes to pick a folder.
                      onPressed: (hasRequests || _hasLogRecords) && !_exporting
                          ? _export
                          : null,
                      tooltip: _exportAffordance.tooltip,
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      onPressed: _clearAction(),
                      tooltip: _view == _View.requests
                          ? 'Clear all requests'
                          : 'Clear all log records',
                    ),
                  ],
                ),
                if (_exportProblem case final problem?)
                  _ExportProblemNotice(
                      problem: problem, hasLogSink: _logSink != null),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SoliplexSpacing.s4,
                    vertical: SoliplexSpacing.s2,
                  ),
                  child: SegmentedButton<_View>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(
                        value: _View.requests,
                        label: Text('Requests'),
                      ),
                      ButtonSegment(value: _View.logs, label: Text('Logs')),
                    ],
                    selected: {_view},
                    onSelectionChanged: (selection) =>
                        setState(() => _view = selection.first),
                  ),
                ),
                Expanded(
                  child: switch (_view) {
                    _View.requests => RequestsPane(
                        inspector: widget.inspector,
                        runId: _runId,
                        onRunFilterCleared: () => setState(() => _runId = null),
                      ),
                    _View.logs => LogsPane(sink: _logSink),
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Clears whichever capture is on screen, so the action never looks live
  /// while doing nothing to the visible list. Null disables it when there is
  /// nothing to clear.
  VoidCallback? _clearAction() {
    if (_view == _View.logs) {
      final sink = _logSink;
      if (sink == null || !_hasLogRecords) return null;
      return sink.clear;
    }
    if (widget.inspector.events.isEmpty &&
        widget.inspector.concurrencyEvents.isEmpty) {
      return null;
    }
    return widget.inspector.clear;
  }

  /// How long to wait on the save dialog before giving up on it.
  ///
  /// Generous, because the user may be browsing folders — but bounded, because
  /// a platform future that never completes would leave the in-flight guard
  /// set and the action permanently, invisibly dead. Android's picker has
  /// result codes it never resolves.
  static const _saveTimeout = Duration(minutes: 5);

  /// How long a success glyph stays before reverting. The notice has no
  /// equivalent: it is the lasting account of a failure.
  static const _feedbackRevert = Duration(seconds: 2);

  /// Writes the captured traffic and log records to a file the user chooses.
  ///
  /// Guards against a second run while one is in flight, and catches the
  /// report building as well as the save: an error while building would
  /// otherwise escape into a future nobody awaits, and this app installs no
  /// zone handler, so it would reach no sink and no surface at all.
  Future<void> _export() async {
    if (_exporting) {
      // Reachable while a non-modal dialog is open, and the button is disabled
      // for exactly that window, so a tap that lands here is worth a trace.
      _logger.info('An export is already in flight; ignoring the request');
      return;
    }
    setState(() => _exporting = true);
    // The glyph resets now; the notice does not. It is the only account of the
    // previous failure, and an attempt that ends in a dismissed dialog would
    // otherwise erase the name of a file the user still has to go look at.
    _exportRevertTimer?.cancel();
    if (_exportFeedback != _ExportFeedback.idle) {
      setState(() => _exportFeedback = _ExportFeedback.idle);
    }
    try {
      await _writeReport();
    } on Object catch (e, st) {
      _logger.error(
        'Building the report failed; nothing was written',
        error: e,
        stackTrace: st,
      );
      _showExportFeedback(_ExportFeedback.failed);
      _setExportProblem(kind: _ExportFailure.reportNotBuilt);
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      } else {
        _exporting = false;
      }
    }
  }

  /// Builds the report and offers it to the platform's save dialog.
  ///
  /// A failure is reported and nothing else happens. There is deliberately no
  /// clipboard fallback: the user asked for a file, and silently overwriting
  /// whatever they had copied is not that. Nothing is stranded either way —
  /// the records stay readable in the Logs pane.
  Future<void> _writeReport() async {
    final sink = _logSink;
    final startedAt = DateTime.now();
    final stamp = startedAt
        .toUtc()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .split('T')
        .join('_');
    final fileName = 'diagnostics_$stamp.txt';

    // Both captures and no filters, whichever pane is showing: a report is
    // read as the whole session, and a reader cannot tell that something was
    // filtered out rather than never recorded.
    final report = buildDiagnosticsReport(
      appName: widget.appName,
      // Chronological, unlike the on-screen list: a report is read top to
      // bottom as a timeline, alongside log records that are already in that
      // order.
      groups: groupHttpEvents(widget.inspector.events),
      generatedAt: startedAt,
      // Null when nothing is collecting, which the report states rather than
      // reporting as an empty capture. Copied because the sink's view is live
      // over its ring buffer.
      renderedLogRecords: sink == null
          ? null
          : List.of(sink.records)
              .map((r) => formatLogRecord(r, includeStackTrace: true))
              .toList(),
      concurrencyEvents: widget.inspector.concurrencyEvents,
      logLevel: LogManager.instance.minimumLevel.label,
    );

    var timedOut = false;
    final save = FilePicker.saveFile(
      dialogTitle: 'Save diagnostics report',
      fileName: fileName,
      bytes: Uint8List.fromList(utf8.encode(report)),
    );
    // Attached before the wait is bounded. Once `timeout` fires, the original
    // future's own callbacks stop running, so a failure arriving late would be
    // consumed and reported nowhere at all.
    unawaited(save.then(
      (path) {
        if (timedOut) {
          _logger.info(
            'The save dialog answered after the export gave up waiting',
            attributes: {'fileName': fileName, 'chosePath': path != null},
          );
        }
      },
      onError: (Object e, StackTrace st) {
        if (timedOut) {
          _logger.error(
            'The save dialog failed after the export gave up waiting',
            error: e,
            stackTrace: st,
            attributes: {'fileName': fileName},
          );
        }
      },
    ));

    try {
      final path = await save.timeout(_saveTimeout, onTimeout: () {
        timedOut = true;
        throw TimeoutException('the save dialog did not answer', _saveTimeout);
      });

      // Web has no dialog and no cancellation: the download is dispatched and
      // null comes back either way. Whether the browser actually delivered it
      // cannot be observed from here, so the claim stops at "started" — saying
      // "saved" would leave a user who was silently blocked believing they
      // have a report they never got.
      if (kIsWeb) {
        _showExportFeedback(_ExportFeedback.downloadStarted);
        _clearExportProblem();
        return;
      }
      if (path != null) {
        _showExportFeedback(_ExportFeedback.savedToFile);
        _clearExportProblem();
        return;
      }
      // Null with no throw. A dismissed dialog on macOS, Android and iOS — but
      // Linux returns null for a failed portal request and Windows for any
      // CommDlgExtendedError, and neither is distinguishable from a cancel
      // here. Left silent on screen, since a cancel is by far the likely case
      // and the user asked for nothing; recorded so that the other case is at
      // least in the log and in the next report.
      _logger.warning(
        'The save dialog returned no path; the report was not written',
        attributes: {
          'fileName': fileName,
          'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        },
      );
      return;
      // A timeout is neither a decline nor a failure: the dialog is still open
      // and still the user's to finish, so this reports that it gave up
      // waiting rather than claiming the save failed.
    } on TimeoutException catch (e, st) {
      _logger.error(
        'The save dialog did not answer in time; the export was abandoned '
        'while it was still open',
        error: e,
        stackTrace: st,
        attributes: {'fileName': fileName},
      );
      _showExportFeedback(_ExportFeedback.failed);
      _setExportProblem(
        kind: _ExportFailure.saveNeverAnswered,
        fileName: fileName,
      );
      return;
      // `on Object`, not `on Exception`: file_picker throws ArgumentError and
      // UnimplementedError from its platform legs, and an Error escaping here
      // would leave the button doing nothing at all, forever, with no record
      // of why. Matches pick_file_impl.dart.
    } on Object catch (e, st) {
      // A desktop save writes the bytes after the dialog closes, so the file
      // it chose may exist and be truncated. Deleting it would not undo that —
      // an overwrite already discarded whatever was there — so the only useful
      // thing is to name it.
      _logger.error(
        'Saving the report to a file failed; on a desktop platform a file of '
        'this name may exist and be incomplete',
        error: e,
        stackTrace: st,
        attributes: {'fileName': fileName},
      );
      _showExportFeedback(_ExportFeedback.failed);
      _setExportProblem(kind: _ExportFailure.saveFailed, fileName: fileName);
    }
  }

  void _setExportProblem({required _ExportFailure kind, String? fileName}) {
    if (!mounted) return;
    setState(() =>
        _exportProblem = (at: DateTime.now(), kind: kind, fileName: fileName));
  }

  void _clearExportProblem() {
    if (mounted && _exportProblem != null) {
      setState(() => _exportProblem = null);
    }
  }

  /// Reverts to the idle glyph after a beat so the action does not read as
  /// permanently "done". The notice, unlike the glyph, stays put.
  void _showExportFeedback(_ExportFeedback value) {
    if (!mounted) return;
    setState(() => _exportFeedback = value);
    _exportRevertTimer?.cancel();
    _exportRevertTimer = Timer(_feedbackRevert, () {
      if (mounted) setState(() => _exportFeedback = _ExportFeedback.idle);
    });
  }

  ({IconData icon, Color? color, String tooltip}) get _exportAffordance =>
      switch (_exportFeedback) {
        _ExportFeedback.idle => (
            // Saves a file; it does not open a share sheet.
            icon: Icons.save_alt,
            color: null,
            tooltip: 'Save report (all requests and log records)',
          ),
        _ExportFeedback.savedToFile => (
            icon: Icons.check,
            color: null,
            tooltip: 'Report saved'
          ),
        _ExportFeedback.downloadStarted => (
            icon: Icons.check,
            color: null,
            tooltip: 'Download started — check your browser downloads',
          ),
        _ExportFeedback.failed => (
            icon: Icons.error_outline,
            color: Theme.of(context).colorScheme.error,
            tooltip: 'Could not save the report',
          ),
      };
}

/// Says what a failed save left behind, and stays until the next attempt that
/// produces an outcome — a dismissed dialog deliberately leaves it standing.
///
/// The failure needs words, not a glyph: on a desktop platform the save writes
/// after the dialog closes, so a file may exist and be truncated. It is stamped
/// because it outlives its attempt, and without a time a standing notice reads
/// as the verdict on whatever the user did last. Selectable because the
/// filename is the part a user has to quote.
class _ExportProblemNotice extends StatelessWidget {
  const _ExportProblemNotice({required this.problem, required this.hasLogSink});

  final _ExportProblem problem;

  /// Whether pointing the user at the Logs pane would lead anywhere.
  final bool hasLogSink;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fileName = problem.fileName;
    final what = switch (problem.kind) {
      _ExportFailure.reportNotBuilt => 'Nothing was written.',
      _ExportFailure.saveNeverAnswered =>
        'The save dialog did not answer, so nothing has been saved. If you '
            'finish it, the file will still be written.',
      // No file is ever written on web — the download is dispatched from
      // memory — so naming one to go and distrust would send the user hunting
      // for something that cannot exist.
      _ExportFailure.saveFailed when kIsWeb => 'Could not download the report.',
      // Deliberately hedged: the dialog lets the user rename, and it returns
      // the path it used only on success, so this is the name that was
      // offered, not necessarily the name of the file now on disk.
      _ExportFailure.saveFailed =>
        'Could not finish saving the report. A partly-written file may have '
            'been left where you chose, probably named $fileName.',
    };
    final pointer = hasLogSink ? ' Details are in the Logs pane.' : '';
    final at = '${problem.at.toUtc().toIso8601String()}: ';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s4,
        vertical: SoliplexSpacing.s2,
      ),
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.error_outline,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: SoliplexSpacing.s3),
          Expanded(
            child: SelectableText(
              '$at$what$pointer',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
