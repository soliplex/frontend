/// Pieces the members card and its list share.
library;

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../../../shared/copy_button.dart';

/// A warning on a tinted surface, in the card's flow.
class AccessNotice extends StatelessWidget {
  const AccessNotice(
      {required this.text, this.icon = Icons.warning_amber, super.key});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = SoliplexTheme.of(context).colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onWarningContainer),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onWarningContainer),
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
