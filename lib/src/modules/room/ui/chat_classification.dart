/// The room's confidentiality marking as it appears inside the chat itself:
/// a band over the conversation ([ChatClassificationBand]) and a sentence
/// under the composer ([ChatClassificationNotice]).
///
/// Both resolve the ambient [ClassificationTheme]'s default — no per-room
/// value exists yet (`Room` carries no classification and the backend sends
/// none), so a deployment's rooms all read the same marking. When that value
/// reaches the wire, these two widgets and `RoomMarkingsRow` in the lobby are
/// the places that take an id.
library;

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Design-system exception: half a step under [SoliplexSpacing.s1] (4), the
/// smallest step the scale carries.
///
/// The band is chrome the conversation pays for on every screen at every
/// width, so its height is worth buying down. At s1 the strip reads as a
/// second toolbar; here it reads as a rule carrying a word. The scale has no
/// smaller step by design — every `sN` is `4 × N`, so a 2 could only enter it
/// under a name that lies about its size.
const double _bandVerticalPadding = 2;

/// Whether the deployment has configured any markings at all.
///
/// Mirrors [SoliplexClassificationBadge]'s own suppression rule: the neutral
/// built-in level is detected by identity, and an unconfigured product should
/// not sprout meaningless markings — neither a pill nor a sentence about one.
bool _classificationConfigured(BuildContext context) => !identical(
      ClassificationTheme.of(context).resolve(context, null),
      ClassificationTheme.fallbackLevel,
    );

/// The room's marking, banded across the full width of the chat directly
/// above the conversation — under the app bar on narrow layouts, under the
/// in-page header on wide ones.
///
/// A row of its own rather than an element of the header: a marking is a
/// fixed cost, and the header's width is not. Sharing that width, the marking
/// takes what it needs and the room name and server pay for it — at the
/// widths phones and split-screen tablets run at, a twelve-character label
/// leaves nothing of the name. Banded, it costs one line of height at every
/// width and identification keeps the bar.
///
/// Full-bleed in the level's own colors, the way a marking is banded on a
/// document. The label centres and wraps rather than truncating — clipping a
/// marking is an integrity bug — which the full width makes room for.
class ChatClassificationBand extends StatelessWidget {
  const ChatClassificationBand({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_classificationConfigured(context)) return const SizedBox.shrink();
    final level = ClassificationTheme.of(context).resolve(context, null);
    return Semantics(
      label: 'Classification: ${level.label}',
      child: ExcludeSemantics(
        child: ColoredBox(
          color: level.background,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SoliplexSpacing.s4,
                vertical: _bandVerticalPadding,
              ),
              child: Text(
                level.label,
                textAlign: TextAlign.center,
                // Tighter leading than the body scale carries: the marking is
                // a single line of caps in a band, not a paragraph, and the
                // band should not cost the conversation more height than the
                // word needs.
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: level.foreground,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The standing reminder under the composer — the same slot the "may make
/// mistakes" line occupies in other chat products — naming the level the
/// user is about to type into.
///
/// The marking's own label is interpolated verbatim, as everywhere else a
/// level is rendered.
class ChatClassificationNotice extends StatelessWidget {
  const ChatClassificationNotice({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_classificationConfigured(context)) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final level = ClassificationTheme.of(context).resolve(context, null);
    return Padding(
      padding: const EdgeInsets.only(
        left: SoliplexSpacing.s4,
        right: SoliplexSpacing.s4,
        bottom: SoliplexSpacing.s2,
      ),
      child: Text(
        'Information level is ${level.label} for this room',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}
