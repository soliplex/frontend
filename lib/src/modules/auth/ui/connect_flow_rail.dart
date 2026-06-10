import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../connect_flow.dart';

/// One node in the [ConnectFlowRail] breadcrumb.
///
/// Mirrors the [ConnectState] sealed hierarchy. The two `optional` steps
/// (insecure / consent) only appear in some runs — an `http://` probe or a
/// server-configured consent notice — so they render dimmed until reached.
enum ConnectStep {
  url('URL'),
  probe('Probe'),
  insecure('Insecure?', optional: true),
  consent('Consent', optional: true),
  provider('Provider'),
  auth('Auth'),
  connected('Connected');

  const ConnectStep(this.label, {this.optional = false});

  final String label;
  final bool optional;
}

/// Maps the live [ConnectState] onto its [ConnectStep] node.
ConnectStep stepForConnectState(ConnectState state) => switch (state) {
      UrlInput() => ConnectStep.url,
      Probing() => ConnectStep.probe,
      InsecureWarning() => ConnectStep.insecure,
      Consent() => ConnectStep.consent,
      ProviderSelection() => ConnectStep.provider,
      Authenticating() => ConnectStep.auth,
      Connected() => ConnectStep.connected,
    };

/// A horizontal breadcrumb of the [ConnectFlow] state machine, surfacing
/// where the user is in the connect → authenticate journey.
///
/// Shown only on wide viewports (the caller gates on
/// [SoliplexBreakpoints.desktop]); on narrow screens the per-state heading
/// carries the context instead. The strip scales down to fit its column so
/// it never overflows.
class ConnectFlowRail extends StatelessWidget {
  const ConnectFlowRail({super.key, required this.current});

  final ConnectStep current;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final baseStyle = context
        .monospaceOn(theme.textTheme.labelSmall)
        .copyWith(color: colors.onSurfaceVariant);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SoliplexSpacing.s3,
        vertical: SoliplexSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        border: Border.all(color: colors.outlineVariant),
        borderRadius: BorderRadius.circular(soliplexRadii.md),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final step in ConnectStep.values) ...[
              _RailNode(step: step, current: current, baseStyle: baseStyle),
              if (step != ConnectStep.values.last)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SoliplexSpacing.s1,
                  ),
                  child: Text(
                    '→',
                    style: baseStyle.copyWith(color: colors.outline),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RailNode extends StatelessWidget {
  const _RailNode({
    required this.step,
    required this.current,
    required this.baseStyle,
  });

  final ConnectStep step;
  final ConnectStep current;
  final TextStyle baseStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isActive = step == current;
    final isDone = step.index < current.index;
    final dimOptional = step.optional && !isActive && !isDone;

    final Color foreground;
    if (isActive) {
      foreground = colors.onPrimary;
    } else if (isDone) {
      foreground = colors.onSurface;
    } else {
      foreground = colors.onSurfaceVariant;
    }

    return Opacity(
      opacity: dimOptional ? 0.5 : 1,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s2,
          vertical: SoliplexSpacing.s1,
        ),
        decoration: isActive
            ? BoxDecoration(
                color: colors.primary,
                borderRadius: BorderRadius.circular(soliplexRadii.sm),
              )
            : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isDone) ...[
              Icon(Icons.check, size: 12, color: foreground),
              const SizedBox(width: SoliplexSpacing.s1),
            ],
            Text(
              step.label,
              style: baseStyle.copyWith(
                color: foreground,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
