/// Pieces the members card and its list share.
library;

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../../../shared/copy_button.dart';

/// How much a notice asks of the reader.
enum NoticeTone {
  /// Worth a second look.
  warning,

  /// Something failed.
  error,
}

/// A message on a tinted surface, in the card's flow, with an optional title.
class AccessNotice extends StatelessWidget {
  const AccessNotice({
    required this.text,
    this.title,
    this.tone = NoticeTone.warning,
    this.icon,
    super.key,
  });

  final String text;
  final String? title;
  final NoticeTone tone;

  /// Defaults to the tone's own icon.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = SoliplexTheme.of(context).colors;
    final style = Theme.of(context).textTheme;
    // An error has a container surface of its own, which a failure uses
    // rather than the danger colour.
    final (background, foreground, defaultIcon) = switch (tone) {
      NoticeTone.warning => (
          colors.warningContainer,
          colors.onWarningContainer,
          Icons.warning_amber,
        ),
      NoticeTone.error => (
          scheme.errorContainer,
          scheme.onErrorContainer,
          Icons.error_outline,
        ),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon ?? defaultIcon, size: 18, color: foreground),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title case final title?) ...[
                  Text(
                    title,
                    style: style.titleSmall?.copyWith(color: foreground),
                  ),
                  const SizedBox(height: SoliplexSpacing.s1),
                ],
                Text(
                  text,
                  style: style.bodySmall?.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The one way forward when the card can't act: the command, ready to copy.
class ServerCommand extends StatelessWidget {
  const ServerCommand(this.command, {super.key});

  final String command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        SoliplexSpacing.s1,
        SoliplexSpacing.s1,
        SoliplexSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              command,
              style: context.monospaceOn(theme.textTheme.bodySmall),
            ),
          ),
          CopyButton(text: command, tooltip: 'Copy command', iconSize: 18),
        ],
      ),
    );
  }
}

/// The room's state, always in the same colours: green while it is as closed
/// as a policy makes it, warning once anyone can read it.
class StateBadge extends StatelessWidget {
  const StateBadge(
      {required this.label,
      required this.icon,
      required this.intent,
      super.key});

  final String label;
  final IconData icon;
  final BadgeIntent intent;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Changed on the server, with room-authz',
        child: SoliplexBadge(
          label: Text(label),
          icon: Icon(icon),
          intent: intent,
        ),
      );
}
