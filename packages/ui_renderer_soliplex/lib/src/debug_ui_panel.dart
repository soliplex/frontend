import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:ui_plugin/ui_plugin.dart';

/// Developer harness panel for [UiPlugin].
///
/// Shows the current [UiPlugin.stateSignal] value and — when a confirm is
/// pending — approve/deny buttons to drive the flow from a test harness
/// without needing the real Soliplex chat UI.
///
/// Pass [renderer] to also get quick-inject buttons for testing
/// [SystemInfoMessage] rendering.
///
/// Mount in a dev-only right panel or overlay:
/// ```dart
/// DebugUiPanel(plugin: uiPlugin, renderer: uiRenderer)
/// ```
class DebugUiPanel extends StatelessWidget {
  const DebugUiPanel({super.key, required this.plugin, this.renderer});

  final UiPlugin plugin;

  /// Optional renderer — enables the inject-test-message section.
  final UiRenderer? renderer;

  @override
  Widget build(BuildContext context) {
    final state = plugin.stateSignal.watch(context);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('UiPlugin', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            _StateRow(state: state),
            if (state is UiAwaitingConfirm) ...[
              const SizedBox(height: 8),
              _ConfirmButtons(verb: state.verb),
            ],
            if (renderer != null) ...[
              const SizedBox(height: 8),
              const Divider(height: 1),
              const SizedBox(height: 8),
              _InjectSection(renderer: renderer!),
            ],
          ],
        ),
      ),
    );
  }
}

class _StateRow extends StatelessWidget {
  const _StateRow({required this.state});

  final UiSessionState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (state) {
      UiIdle() => ('Idle', theme.colorScheme.onSurfaceVariant),
      UiAwaitingConfirm(:final verb) => (
          'Awaiting confirm: $verb',
          theme.colorScheme.error,
        ),
      UiModalOpen(:final title) => (
          'Modal open: $title',
          theme.colorScheme.primary
        ),
      UiFormOpen(:final schemaKey) => (
          'Form open ($schemaKey)',
          theme.colorScheme.secondary,
        ),
    };

    return Row(
      children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 6),
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
      ],
    );
  }
}

class _ConfirmButtons extends StatelessWidget {
  const _ConfirmButtons({required this.verb});

  final String verb;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        FilledButton.tonal(
          onPressed: () {},
          child: const Text('Approve'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: () {},
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: const Text('Deny'),
        ),
        const SizedBox(width: 8),
        Text(
          '(drive via FakeUiRenderer in tests)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _InjectSection extends StatefulWidget {
  const _InjectSection({required this.renderer});

  final UiRenderer renderer;

  @override
  State<_InjectSection> createState() => _InjectSectionState();
}

class _InjectSectionState extends State<_InjectSection> {
  final _controller = TextEditingController(
    text: '**Hello** from `ui_inject_message`! This is _markdown_.',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _inject(String? format) {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.renderer.injectMessage(content: text, format: format);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Inject test message',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _controller,
          maxLines: 2,
          style: theme.textTheme.bodySmall,
          decoration: const InputDecoration(
            isDense: true,
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            FilledButton.tonal(
              onPressed: () => _inject('markdown'),
              child: const Text('Markdown'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: () => _inject('plain'),
              child: const Text('Plain'),
            ),
          ],
        ),
      ],
    );
  }
}
