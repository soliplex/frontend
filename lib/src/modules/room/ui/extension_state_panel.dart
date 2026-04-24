import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../thread_view_state.dart';

/// Collapsible debug panel that renders live reactive state for every
/// [StatefulSessionExtension] in the active [AgentSession].
///
/// Iterates [ThreadViewState.statefulObservations] to obtain
/// `(namespace, signal)` pairs, then renders a row per extension that
/// rebuilds independently as each signal changes. The panel watches
/// [ThreadViewState.sessionState] so it rebuilds when the session attaches
/// or detaches.
class ExtensionStatePanel extends StatefulWidget {
  const ExtensionStatePanel({super.key, required this.threadView});
  final ThreadViewState threadView;

  @override
  State<ExtensionStatePanel> createState() => _ExtensionStatePanelState();
}

class _ExtensionStatePanelState extends State<ExtensionStatePanel> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    // Rebuild when a session attaches/detaches so the observation list
    // reflects the currently active extensions.
    widget.threadView.sessionState.watch(context);
    final observations = widget.threadView.statefulObservations.toList();
    if (observations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHigh,
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.extension,
                    size: 16,
                    color: theme.colorScheme.secondary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'EXTENSIONS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.1,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondaryContainer,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${observations.length}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
          if (_isExpanded)
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (namespace, signal) in observations)
                      _ExtensionRow(namespace: namespace, signal: signal),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ExtensionRow extends StatelessWidget {
  const _ExtensionRow({required this.namespace, required this.signal});
  final String namespace;
  final ReadonlySignal<Object?> signal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = signal.watch(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            namespace,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _encode(value),
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              fontSize: 10,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 6,
            overflow: TextOverflow.ellipsis,
          ),
          const Divider(height: 12),
        ],
      ),
    );
  }

  static String _encode(Object? value) {
    try {
      return const JsonEncoder.withIndent('  ').convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}
