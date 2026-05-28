import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' show ReadonlySignal;
import 'package:soliplex_design/soliplex_design.dart';

/// The "are you still there?" modal shown when inactivity is detected.
///
/// The countdown is driven by the `graceDeadline` signal exposed by
/// `InactivityMonitor`. Tapping "Stay signed in" calls [onExtend];
/// tapping "Sign out now" calls [onLogout]. The shell drives showing
/// and dismissing the dialog via `InactivityMonitor.warningVisible`,
/// so the dialog itself never pops its own route.
class InactivityDialog extends StatefulWidget {
  const InactivityDialog({
    super.key,
    required this.graceDeadline,
    required this.onExtend,
    required this.onLogout,
  });

  final ReadonlySignal<DateTime?> graceDeadline;
  final VoidCallback onExtend;
  final VoidCallback onLogout;

  @override
  State<InactivityDialog> createState() => _InactivityDialogState();
}

class _InactivityDialogState extends State<InactivityDialog> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Duration _remainingFor(DateTime? deadline) {
    if (deadline == null) return Duration.zero;
    final diff = deadline.difference(clock.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  String _formatRemaining(Duration remaining) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  String _semanticsLabelFor(Duration remaining) {
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return 'Time remaining: $minutes minutes $seconds seconds';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final remaining = _remainingFor(widget.graceDeadline.value);

    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Still there?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "You've been inactive for a while. You'll be signed out in:",
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: SoliplexSpacing.s2),
            Semantics(
              label: _semanticsLabelFor(remaining),
              excludeSemantics: true,
              child: Text(
                _formatRemaining(remaining),
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        actions: [
          SoliplexButton.text(
            onPressed: widget.onLogout,
            intent: ButtonIntent.danger,
            child: const Text('Sign out now'),
          ),
          SoliplexButton.filled(
            onPressed: widget.onExtend,
            child: const Text('Stay signed in'),
          ),
        ],
      ),
    );
  }
}
