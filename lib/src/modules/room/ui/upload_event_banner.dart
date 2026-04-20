import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';

/// Transient inline notifications that announce upload transitions the
/// user may have missed while focused on the composer.
///
/// Derives events by diffing `UploadsStatus` snapshots for the current
/// room scope and (when set) thread scope. Successes aggregate and
/// auto-dismiss after 4 seconds; failures stay sticky until dismissed.
/// Pre-existing state on scope entry does not fire a pill — the chip
/// and file panel already communicate it.
class UploadEventBanner extends StatefulWidget {
  const UploadEventBanner({
    required this.tracker,
    required this.roomId,
    required this.threadId,
    super.key,
  });

  final UploadTracker tracker;
  final String roomId;
  final String? threadId;

  @override
  State<UploadEventBanner> createState() => _UploadEventBannerState();
}

class _UploadEventBannerState extends State<UploadEventBanner> {
  static const _successDismissDelay = Duration(seconds: 4);

  List<DisplayUpload>? _prevRoom;
  List<DisplayUpload>? _prevThread;
  final List<String> _successes = [];
  final List<_FailureEvent> _failures = [];
  Timer? _successTimer;
  VoidCallback? _unsubRoom;
  VoidCallback? _unsubThread;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant UploadEventBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final scopeChanged = oldWidget.tracker != widget.tracker ||
        oldWidget.roomId != widget.roomId ||
        oldWidget.threadId != widget.threadId;
    if (!scopeChanged) return;
    _unsubscribe();
    _prevRoom = null;
    _prevThread = null;
    _successes.clear();
    _failures.clear();
    _successTimer?.cancel();
    _successTimer = null;
    _subscribe();
  }

  @override
  void dispose() {
    _unsubscribe();
    _successTimer?.cancel();
    super.dispose();
  }

  void _subscribe() {
    _unsubRoom = widget.tracker
        .roomUploads(widget.roomId)
        .subscribe((status) => _onSnapshot(status, isRoom: true));
    final threadId = widget.threadId;
    if (threadId != null) {
      _unsubThread = widget.tracker
          .threadUploads(widget.roomId, threadId)
          .subscribe((status) => _onSnapshot(status, isRoom: false));
    }
  }

  void _unsubscribe() {
    _unsubRoom?.call();
    _unsubThread?.call();
    _unsubRoom = null;
    _unsubThread = null;
  }

  void _onSnapshot(UploadsStatus status, {required bool isRoom}) {
    if (!mounted) return;
    final current = status is UploadsLoaded ? status.uploads : null;
    if (current == null) return;
    final prev = isRoom ? _prevRoom : _prevThread;
    final events = _diff(prev, current);
    if (isRoom) {
      _prevRoom = current;
    } else {
      _prevThread = current;
    }
    if (events.isEmpty) return;

    setState(() {
      for (final event in events) {
        switch (event) {
          case _CompletedEvent(:final filename):
            _successes.add(filename);
          case _FailureEvent():
            _failures.add(event);
        }
      }
      if (_successes.isNotEmpty) {
        _successTimer?.cancel();
        _successTimer = Timer(_successDismissDelay, _clearSuccesses);
      }
    });
  }

  /// Returns the list of transition events between [prev] and [current].
  /// Null [prev] means this is the baseline snapshot — no events.
  List<_Event> _diff(List<DisplayUpload>? prev, List<DisplayUpload> current) {
    if (prev == null) return const [];
    final events = <_Event>[];
    final currentById = {
      for (final e in current)
        if (e is PendingUpload) e.id: e else if (e is FailedUpload) e.id: e,
    };
    final persistedNames = {
      for (final e in current)
        if (e is PersistedUpload) e.filename,
    };
    for (final entry in prev) {
      if (entry is! PendingUpload) continue;
      final match = currentById[entry.id];
      if (match is FailedUpload) {
        events.add(_FailureEvent(entry.filename, match.message));
      } else if (match == null && persistedNames.contains(entry.filename)) {
        events.add(_CompletedEvent(entry.filename));
      }
    }
    return events;
  }

  void _clearSuccesses() {
    if (!mounted) return;
    setState(() {
      _successes.clear();
      _successTimer = null;
    });
  }

  void _dismissSuccesses() {
    _successTimer?.cancel();
    setState(() {
      _successes.clear();
      _successTimer = null;
    });
  }

  void _dismissFailures() {
    setState(() => _failures.clear());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _AnimatedPill(child: _failurePill(theme)),
          _AnimatedPill(child: _successPill(theme)),
        ],
      ),
    );
  }

  Widget _failurePill(ThemeData theme) {
    if (_failures.isEmpty) return const SizedBox.shrink();
    final message = _failures.length == 1
        ? 'Failed to upload ${_failures.first.filename}: '
            '${_failures.first.message}'
        : 'Failed to upload ${_failures.length} files';
    return _Pill(
      icon: Icons.error_outline,
      background: theme.colorScheme.errorContainer,
      foreground: theme.colorScheme.onErrorContainer,
      message: message,
      onDismiss: _dismissFailures,
    );
  }

  Widget _successPill(ThemeData theme) {
    if (_successes.isEmpty) return const SizedBox.shrink();
    final message = _successes.length == 1
        ? 'Uploaded ${_successes.first}'
        : 'Uploaded ${_successes.first} and ${_successes.length - 1} more';
    // Material doesn't have a "success" color token; use light-green
    // Material shades so success reads distinctly from the primary
    // color without competing with the errorContainer on failures.
    return _Pill(
      icon: Icons.check_circle_outline,
      background: Colors.green.shade100,
      foreground: Colors.green.shade900,
      message: message,
      onDismiss: _dismissSuccesses,
    );
  }
}

class _AnimatedPill extends StatelessWidget {
  const _AnimatedPill({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 150),
      child: child,
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.background,
    required this.foreground,
    required this.message,
    required this.onDismiss,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 12, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      constraints: const BoxConstraints(maxWidth: 420),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: foreground),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              message,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: foreground),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.close, size: 14),
            color: foreground,
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}

sealed class _Event {
  const _Event();
}

class _CompletedEvent extends _Event {
  const _CompletedEvent(this.filename);
  final String filename;
}

class _FailureEvent extends _Event {
  const _FailureEvent(this.filename, this.message);
  final String filename;
  final String message;
}
