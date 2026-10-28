import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart' show WorkdirFile;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../workdir_files_status.dart';
import '../workspace_groups.dart';
import 'notice_pill.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.workspace_event_banner');

/// A transient notice that files were added to the open thread's workspace,
/// with a Show action that opens the files panel.
///
/// Derives the added files by diffing the paths of successive
/// [WorkdirFilesLoaded] listings. The first listing seen for a thread is the
/// baseline and fires nothing. Within a room visit, returning to a thread
/// re-baselines on its cached listing, so files added while away are
/// announced when the reopening fetch lands. Loading and Failed listings are
/// skipped, and a path that disappears never fires, nor does one inside a
/// tooling directory (see [isToolingPath]): a commit or an import there is not
/// news. The notice names the first added file, in path order, by its
/// basename.
class WorkspaceEventBanner extends StatefulWidget {
  const WorkspaceEventBanner({
    required this.status,
    required this.threadId,
    required this.onShow,
    super.key,
  });

  final ReadonlySignal<WorkdirFilesStatus> status;
  final String threadId;
  final VoidCallback onShow;

  @override
  State<WorkspaceEventBanner> createState() => _WorkspaceEventBannerState();
}

class _WorkspaceEventBannerState extends State<WorkspaceEventBanner> {
  Set<String>? _previous;

  /// Added files not yet dismissed, in path order.
  final SplayTreeSet<WorkdirFile> _added =
      SplayTreeSet((a, b) => a.filename.compareTo(b.filename));
  Timer? _dismissTimer;
  VoidCallback? _unsubscribe;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant WorkspaceEventBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status == widget.status &&
        oldWidget.threadId == widget.threadId) {
      return;
    }
    _unsubscribe?.call();
    _previous = null;
    _added.clear();
    _dismissTimer?.cancel();
    _dismissTimer = null;
    _subscribe();
  }

  @override
  void dispose() {
    _unsubscribe?.call();
    _dismissTimer?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _unsubscribe = widget.status.subscribe(_onStatus);
  }

  void _onStatus(WorkdirFilesStatus status) {
    if (!mounted || status is! WorkdirFilesLoaded) return;
    final paths = {for (final f in status.files) f.filename};
    final previous = _previous;
    _previous = paths;
    if (previous == null) {
      _logger.debug(
        'workspace pill baseline threadId=${widget.threadId} '
        'count=${paths.length}',
      );
      return;
    }
    final added = [
      for (final f in status.files)
        if (!previous.contains(f.filename) && !isToolingPath(f.filename)) f,
    ];
    if (added.isEmpty) return;
    _logger.debug(
      'workspace pill shown threadId=${widget.threadId} added=${added.length}',
    );
    setState(() {
      _added.addAll(added);
      _dismissTimer?.cancel();
      _dismissTimer = Timer(successNoticeDismissDelay, () => _dismiss('timer'));
    });
  }

  void _dismiss(String reason) {
    if (!mounted) return;
    _logger.debug('workspace pill dismissed reason=$reason');
    _dismissTimer?.cancel();
    setState(() {
      _added.clear();
      _dismissTimer = null;
    });
  }

  void _show() {
    widget.onShow();
    _dismiss('show');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: Align(
        alignment: Alignment.centerLeft,
        child: AnimatedNoticePill(child: _pill(context)),
      ),
    );
  }

  Widget _pill(BuildContext context) {
    if (_added.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('workspace-empty'));
    }
    final name = _added.first.basename;
    final message = _added.length == 1
        ? 'Added $name to the workspace'
        : 'Added $name and ${_added.length - 1} more to the workspace';
    final colors = SoliplexTheme.of(context).colors;
    return NoticePill(
      key: ValueKey('workspace:$message'),
      icon: Icons.check_circle_outline,
      background: colors.successContainer,
      foreground: colors.onSuccessContainer,
      message: message,
      onDismiss: () => _dismiss('close'),
      actionLabel: 'Show',
      onAction: _show,
    );
  }
}
