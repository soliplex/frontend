/// The room's confidentiality marking as it appears inside the chat itself:
/// a badge in the bar over the conversation ([ChatClassificationBadge]) and a
/// sentence under the composer ([ChatClassificationNotice]).
///
/// Both resolve the ambient [ClassificationTheme]'s default — no per-room
/// value exists yet (`Room` carries no classification and the backend sends
/// none), so a deployment's rooms all read the same marking. When that value
/// reaches the wire, these two widgets and `RoomMarkingsRow` in the lobby are
/// the places that take an id.
library;

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Whether the deployment has configured any markings at all.
///
/// Mirrors [SoliplexClassificationBadge]'s own suppression rule: the neutral
/// built-in level is detected by identity, and an unconfigured product should
/// not sprout meaningless markings — neither a pill nor a sentence about one.
bool _classificationConfigured(BuildContext context) => !identical(
      ClassificationTheme.of(context).resolve(context, null),
      ClassificationTheme.fallbackLevel,
    );

/// The room's marking, mounted in the bar above the conversation beside the
/// room title and its server subtitle.
///
/// Stands as tall as the bar's trailing icon buttons — [kMinInteractiveDimension]
/// is their hit-target height — so the marking reads as part of the bar's
/// furniture rather than as a pill floating in it. The label still wraps
/// inside that height rather than truncating (clipping a marking is an
/// integrity bug); two lines fit, so callers should let this widget take the
/// width it asks for and shrink the room title instead.
///
/// Carries its own leading gap, so a caller placing it after a title does not
/// have to repeat the suppression check to avoid a stray gap on a deployment
/// that configures no markings.
class ChatClassificationBadge extends StatelessWidget {
  const ChatClassificationBadge({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_classificationConfigured(context)) return const SizedBox.shrink();
    return const Padding(
      padding: EdgeInsets.only(left: SoliplexSpacing.s2),
      child: SizedBox(
        height: kMinInteractiveDimension,
        child: SoliplexClassificationBadge.bar(),
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
