import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../thread_view_state.dart';

/// Collapsible debug panel that renders live reactive state for every
/// [StatefulSessionExtension] in the active [AgentSession].
///
/// Iterates [ThreadViewState.statefulObservations] to obtain
/// `(namespace, signal)` pairs, then renders a row per extension that
/// rebuilds independently as each signal changes. The panel itself rebuilds
/// when [ThreadViewState.sessionState] changes (session attached/detached).
class ExtensionStatePanel extends StatefulWidget {
  const ExtensionStatePanel({super.key, required this.threadView});
  final ThreadViewState threadView;

  @override
  State<ExtensionStatePanel> createState() => _ExtensionStatePanelState();
}

class _ExtensionStatePanelState extends State<ExtensionStatePanel> {
  void Function()? _unsub;
  List<(String, ReadonlySignal<Object?>)> _observations = const [];
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _subscribe(widget.threadView);
  }

  @override
  void didUpdateWidget(ExtensionStatePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadView != widget.threadView) {
      _unsub?.call();
      _subscribe(widget.threadView);
    }
  }

  void _subscribe(ThreadViewState view) {
    setState(() {
      _observations = view.statefulObservations.toList();
    });
    _unsub = view.sessionState.subscribe((_) {
      if (!mounted) return;
      setState(() {
        _observations = view.statefulObservations.toList();
      });
    });
  }

  @override
  void dispose() {
    _unsub?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_observations.isEmpty) return const SizedBox.shrink();

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
                      '${_observations.length}',
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
                    for (final (namespace, signal) in _observations)
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
