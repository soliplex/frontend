import 'dart:async';

import 'package:flutter/material.dart';

import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../models/log_record_format.dart';

/// The captured log records, newest first.
///
/// Stateful, and owning its own subscription, so that a record arriving while
/// the request list is on screen does not rebuild this pane: only the selected
/// pane is mounted, so there is nothing here to tell about it. (The screen
/// stays subscribed for its own header actions.)
class LogsPane extends StatefulWidget {
  const LogsPane({required this.sink, super.key});

  /// Null when no memory sink is installed, which this pane reports
  /// differently from a sink with no records: nothing is being collected,
  /// rather than nothing having happened.
  final MemorySink? sink;

  @override
  State<LogsPane> createState() => _LogsPaneState();
}

class _LogsPaneState extends State<LogsPane> {
  final List<StreamSubscription<void>> _subscriptions = [];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  void _subscribe() {
    final sink = widget.sink;
    if (sink == null) return;
    // Both streams matter: without `onClear` the list keeps painting records
    // the sink has already dropped. Neither needs an `onError`: MemorySink
    // only ever calls `add`, never `addError`.
    _subscriptions.addAll([
      sink.onRecord.listen((_) => _rebuild()),
      sink.onClear.listen((_) => _rebuild()),
    ]);
  }

  void _cancel() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    _subscriptions.clear();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sink = widget.sink;

    // Said plainly rather than shown as an empty list: a reader who sees "no
    // records" concludes the code logged nothing and looks elsewhere, when in
    // fact nothing was ever collected to look at.
    if (sink == null) {
      return _Message(
        'No log sink is installed in this build, so no records are being '
        'kept. Their absence here says nothing about what happened.',
      );
    }

    // A snapshot, not the sink's live view. `MemorySink.records` recomputes
    // `length` on every read, and once the buffer is full it also recomputes
    // every index from the current head — so a record written between
    // `ListView.builder` capturing `itemCount` and running `itemBuilder` would
    // shift the rows under it, and a `clear` in that window would throw.
    final records = List.of(sink.records);

    if (records.isEmpty) {
      return _Message('No log records captured.');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Named and counted like the request list, so switching panes doesn't
        // lose track of how much was captured.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s4,
            SoliplexSpacing.s4,
            SoliplexSpacing.s4,
            SoliplexSpacing.s2,
          ),
          child: Text(
            'Log records (${records.length})',
            style: theme.textTheme.titleMedium,
          ),
        ),
        Expanded(
          // Newest first, matching the request list's ordering.
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s4),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[records.length - 1 - index];
              return Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
                child: SelectableText(
                  formatLogRecord(record),
                  style: context.monospaceOn(theme.textTheme.bodySmall),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
