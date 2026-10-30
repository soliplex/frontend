import 'dart:async';

import 'package:flutter/material.dart';
import 'package:soliplex_frontend/src/modules/room/upload_tracker.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'notice_pill.dart';

/// Transient inline notifications that announce upload transitions the
/// user may have missed while focused on the composer.
///
/// Derives events by diffing `UploadsStatus` snapshots for the current
/// room scope and (when set) thread scope. Successes aggregate and
/// auto-dismiss after 4 seconds; failures stay until dismissed here, and
/// each leaves the pill when its failed row is dismissed.
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
    final events = _diff(prev, current, isRoom: isRoom);
    if (isRoom) {
      _prevRoom = current;
    } else {
      _prevThread = current;
    }
    // A failure whose row has left this scope (the user dismissed it) is no
    // longer one the pill should count.
    final failedIds = {
      for (final e in current)
        if (e is FailedUpload) e.id,
    };
    bool isGone(_FailureEvent f) =>
        f.isRoom == isRoom && !failedIds.contains(f.id);
    if (events.isEmpty && !_failures.any(isGone)) return;

    setState(() {
      _failures.removeWhere(isGone);
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
        _successTimer = Timer(successNoticeDismissDelay, _clearSuccesses);
      }
    });
  }

  /// Returns the list of transition events between [prev] and [current].
  /// Null [prev] means this is the baseline snapshot — no events.
  List<_Event> _diff(
    List<DisplayUpload>? prev,
    List<DisplayUpload> current, {
    required bool isRoom,
  }) {
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
        events.add(_FailureEvent(
          id: match.id,
          isRoom: isRoom,
          filename: entry.filename,
          message: match.message,
        ));
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
          AnimatedNoticePill(child: _failurePill(theme)),
          AnimatedNoticePill(child: _successPill(theme)),
        ],
      ),
    );
  }

  Widget _failurePill(ThemeData theme) {
    if (_failures.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('failure-empty'));
    }
    final message = _failures.length == 1
        ? 'Failed to upload ${_failures.first.filename}: '
            '${_failures.first.message}'
        : 'Failed to upload ${_failures.length} files';
    return NoticePill(
      key: ValueKey('failure:$message'),
      icon: Icons.error_outline,
      background: theme.colorScheme.errorContainer,
      foreground: theme.colorScheme.onErrorContainer,
      message: message,
      onDismiss: _dismissFailures,
    );
  }

  Widget _successPill(ThemeData theme) {
    if (_successes.isEmpty) {
      return const SizedBox.shrink(key: ValueKey('success-empty'));
    }
    final message = _successes.length == 1
        ? 'Uploaded ${_successes.first}'
        : 'Uploaded ${_successes.first} and ${_successes.length - 1} more';
    final colors = SoliplexTheme.of(context).colors;
    return NoticePill(
      key: ValueKey('success:$message'),
      icon: Icons.check_circle_outline,
      background: colors.successContainer,
      foreground: colors.onSuccessContainer,
      message: message,
      onDismiss: _dismissSuccesses,
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
  const _FailureEvent({
    required this.id,
    required this.isRoom,
    required this.filename,
    required this.message,
  });

  /// The failed row's id, which leaves its scope when the row is dismissed.
  final String id;
  final bool isRoom;
  final String filename;
  final String message;
}
