/// The room's confidentiality marking as it appears inside the chat itself: a
/// band over the conversation ([ChatClassificationBand]).
///
/// The band takes no room argument, because `Room` carries no classification
/// field: it renders the ambient [ClassificationTheme]'s default, so a
/// deployment's rooms all read the same marking.
library;

import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Half a step under [SoliplexSpacing.s1] (4), the smallest step the scale
/// carries — every `sN` is `4 × N`, so 2 could only enter the scale under a
/// name that lies about its size.
///
/// The band is chrome the conversation pays for on every screen at every
/// width, so its height is worth buying down. At s1 the strip reads as a
/// second toolbar; here it reads as a rule carrying a word.
const double _bandVerticalPadding = 2;

/// The room's marking, banded above the conversation under whatever names the
/// room — the app bar on narrow layouts, the in-page header on wide ones.
///
/// A row of its own rather than an element of the header: a marking is a
/// fixed cost, and the header's width is not. Sharing that width, the marking
/// takes what it needs and the room name and server pay for it — at the widths
/// phones and split-screen tablets run at, a twelve-character label leaves
/// nothing of the name. The two width-pinned tests in `room_screen_test.dart`
/// hold that line.
///
/// Spans its pane uncapped, unlike the width-capped conversation below it: a
/// marking bands the whole surface, the way it does on a document. It takes
/// the level's own colors, and the label centres and wraps rather than
/// truncating — clipping a marking is an integrity bug — which the full width
/// makes room for.
class ChatClassificationBand extends StatelessWidget {
  const ChatClassificationBand({super.key});

  @override
  Widget build(BuildContext context) {
    final classification = ClassificationTheme.of(context);
    // Resolved once, and not asked again to decide whether to render:
    // ClassificationTheme.resolve logs a fail-loud warning for an id it does
    // not recognize, and a second call would double that warning on every
    // build. Null is the deployment that declared no marking vocabulary.
    final level = classification.isConfigured
        ? classification.resolve(context, null)
        : null;
    if (level == null) return const SizedBox.shrink();
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
                // Tighter leading than labelSmall's 1.5: a marking in a band
                // is not a paragraph, and the band should not cost the
                // conversation more height than the text needs.
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
