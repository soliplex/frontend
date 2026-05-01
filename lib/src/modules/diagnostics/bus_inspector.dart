import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// One recorded write to a per-thread `StateBus`.
///
/// Captures the [ThreadKey] context (which the bus itself does not
/// carry), the resolved [tag] (either the writer-supplied label or one
/// inferred from the most recent AG-UI event on the same thread),
/// and a frozen snapshot of the state immediately after the commit.
@immutable
class BusEvent {
  const BusEvent({
    required this.timestamp,
    required this.threadKey,
    required this.tag,
    required this.snapshot,
  });

  final DateTime timestamp;
  final ThreadKey threadKey;
  final String? tag;
  final Map<String, dynamic> snapshot;
}

/// One recorded raw AG-UI event observed on a thread.
///
/// [tag] is derived from the event's runtime type (e.g.
/// `ActivitySnapshotEvent` → `agui.activitysnapshot`) so the existing
/// tag chip + `tag:` filter work uniformly for events and bus commits.
@immutable
class EventRecord {
  EventRecord({
    required this.timestamp,
    required this.threadKey,
    required this.event,
  }) : tag = _tagFor(event);

  final DateTime timestamp;
  final ThreadKey threadKey;
  final BaseEvent event;
  final String tag;

  static String _tagFor(BaseEvent event) {
    final name = event.runtimeType.toString();
    final stripped =
        name.endsWith('Event') ? name.substring(0, name.length - 5) : name;
    return 'agui.${stripped.toLowerCase()}';
  }
}

/// Collects bus events for the bus inspector UI.
///
/// Wired into `AgentRuntime` via its `busObserver` and `eventObserver`
/// constructor parameters: the runtime fans every per-thread bus
/// commit and every raw AG-UI event into this recorder. The agent
/// itself stays free of any tagging logic — the inspector retroactively
/// labels each commit based on the most recent state event observed on
/// the same thread.
///
/// Events are bounded: on overflow, the oldest event is dropped so a
/// long-running session cannot grow memory without bound.
class BusInspector with ChangeNotifier {
  BusInspector({int maxEvents = 1000})
      : _maxEvents = maxEvents > 0
            ? maxEvents
            : throw ArgumentError.value(
                maxEvents,
                'maxEvents',
                'must be positive',
              );

  final int _maxEvents;
  final ListQueue<BusEvent> _events = ListQueue<BusEvent>();
  final ListQueue<EventRecord> _records = ListQueue<EventRecord>();

  /// Most recent AG-UI state event seen per thread, used to infer the
  /// tag for the next bus commit on that thread. Cleared after the
  /// commit consumes it so subsequent untagged commits surface as
  /// `agui.run-state` rather than re-using a stale tag.
  final Map<ThreadKey, BaseEvent> _lastStateEventByThread = {};

  bool _disposed = false;

  /// Recorded bus commits, oldest first.
  List<BusEvent> get events => List.unmodifiable(_events);

  /// Recorded raw AG-UI events, oldest first.
  List<EventRecord> get eventRecords => List.unmodifiable(_records);

  void clear() {
    if (_disposed) return;
    _events.clear();
    _records.clear();
    _lastStateEventByThread.clear();
    notifyListeners();
  }

  /// Sink callable as a `ThreadEventObserver` from `AgentRuntime`.
  /// Records the event for the unified inspector timeline AND tracks
  /// the latest state event per thread so [record] can label the next
  /// bus commit accurately.
  void recordEvent(ThreadKey threadKey, BaseEvent event) {
    if (_disposed) return;
    if (event is StateSnapshotEvent || event is StateDeltaEvent) {
      _lastStateEventByThread[threadKey] = event;
    }
    _records.addLast(
      EventRecord(
        timestamp: DateTime.now(),
        threadKey: threadKey,
        event: event,
      ),
    );
    if (_records.length > _maxEvents) _records.removeFirst();
    notifyListeners();
  }

  /// Sink callable as a `ThreadBusObserver` from `AgentRuntime`.
  /// If [tag] is non-null it is preserved verbatim (used by seed paths
  /// like `seed.initial` / `seed.history`). Otherwise the inspector
  /// infers the tag from the most recent state event on the same
  /// thread; absence of one means the commit was driven by a non-state
  /// run-state transition (tool yielding, run completion, …).
  void record(
    ThreadKey threadKey,
    String? tag,
    Map<String, dynamic> snapshot,
  ) {
    if (_disposed) return;
    final resolved = tag ?? _inferTag(threadKey);
    _events.addLast(
      BusEvent(
        timestamp: DateTime.now(),
        threadKey: threadKey,
        tag: resolved,
        snapshot: snapshot,
      ),
    );
    if (_events.length > _maxEvents) _events.removeFirst();
    notifyListeners();
  }

  String _inferTag(ThreadKey threadKey) {
    final last = _lastStateEventByThread.remove(threadKey);
    if (last is StateSnapshotEvent) return 'agui.snapshot';
    if (last is StateDeltaEvent) return 'agui.delta';
    return 'agui.run-state';
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}
