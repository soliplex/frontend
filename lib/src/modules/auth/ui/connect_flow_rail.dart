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
/// carries the context instead. The strip scrolls horizontally when it's
/// wider than its column, so every label stays legible rather than being
/// squeezed. As the flow advances the active node is scrolled to the centre of
/// the strip; early steps that can't be centred stay pinned at the start (the
/// scroll clamps to its bounds).
class ConnectFlowRail extends StatefulWidget {
  const ConnectFlowRail({super.key, required this.current});

  final ConnectStep current;

  @override
  State<ConnectFlowRail> createState() => _ConnectFlowRailState();
}

class _ConnectFlowRailState extends State<ConnectFlowRail> {
  final GlobalKey _activeKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _centerActiveAfterFrame();
  }

  @override
  void didUpdateWidget(ConnectFlowRail old) {
    super.didUpdateWidget(old);
    if (old.current != widget.current) _centerActiveAfterFrame();
  }

  void _centerActiveAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // The brand type ramp ships only labelMedium / labelSmall for labels, so
    // labelMedium keeps the rail on-token; a larger label style would fall
    // through to Material's off-brand default.
    final baseStyle = theme.textTheme.labelMedium;

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
      // The strip can be wider than its column on smaller desktop windows;
      // scroll rather than shrink so every label stays legible.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final step in ConnectStep.values) ...[
              _RailNode(
                key: step == widget.current ? _activeKey : null,
                step: step,
                current: widget.current,
                baseStyle: baseStyle,
              ),
              if (step != ConnectStep.values.last)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SoliplexSpacing.s1,
                  ),
                  child: Text(
                    '→',
                    style: baseStyle?.copyWith(color: colors.onSurfaceVariant),
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
    super.key,
  });

  final ConnectStep step;
  final ConnectStep current;
  final TextStyle? baseStyle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isActive = step == current;
    // A step is done once the flow is past its position. The branch-only
    // insecure / consent steps are marked done this way too, even on a run
    // that skipped them: the rail only knows `current`, and a stray check on
    // a step the user may not have seen is preferable to leaving a step they
    // did complete unchecked.
    final isDone = step.index < current.index;
    final dimOptional = step.optional && !isActive && !isDone;

    // Active reads on the primary fill; everything else sits at full
    // on-surface contrast so the rail stays readable. Optional steps that
    // haven't been reached are softened with opacity, not a dim color.
    final foreground = isActive ? colors.onPrimary : colors.onSurface;

    return Opacity(
      opacity: dimOptional ? 0.6 : 1,
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
              Icon(Icons.check, size: 16, color: foreground),
              const SizedBox(width: SoliplexSpacing.s1),
            ],
            Text(
              step.label,
              style: baseStyle?.copyWith(
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
