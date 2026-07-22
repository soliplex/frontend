import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_design/soliplex_design.dart';

/// Whether a room's markings row has anything to show: a configured
/// confidentiality marking, a quiz indicator, or both.
///
/// [SoliplexClassificationBadge] renders nothing until a deployment configures
/// classifications, so on a stock build this is driven purely by quizzes. Cards
/// use this to decide whether to spend a dedicated row's worth of layout — the
/// badge itself is always mounted as a seam regardless (see [RoomMarkingsRow]).
bool roomHasVisibleMarkings(BuildContext context, Room room) =>
    room.hasQuizzes || _classificationConfigured(context);

/// Mirrors [SoliplexClassificationBadge]'s own suppression rule: the badge
/// shows nothing only for the unconfigured built-in level, detected by identity.
bool _classificationConfigured(BuildContext context) => !identical(
      ClassificationTheme.of(context).resolve(context, null),
      ClassificationTheme.fallbackLevel,
    );

/// A room's confidentiality marking and quiz indicator, laid out on their own
/// row so a long room name never has to share horizontal space with them
/// (issue #427: markings were squeezing the title on narrow, and on accessible-
/// text-scale, viewports).
///
/// Always mounts [SoliplexClassificationBadge] — it self-suppresses to a
/// zero-size seam until a deployment configures classifications — so callers can
/// rely on the badge being present in the tree. The badge is wrapped in
/// [Flexible] so a long marking wraps within the row instead of overflowing
/// when the user has bumped their text size.
class RoomMarkingsRow extends StatelessWidget {
  const RoomMarkingsRow({super.key, required this.room});

  final Room room;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const Flexible(child: SoliplexClassificationBadge()),
        if (room.hasQuizzes) ...[
          // The badge self-suppresses to zero width when no classification is
          // configured; only pay the gap when it actually occupies space, so
          // the quiz icon sits flush left instead of behind a leading gap.
          if (_classificationConfigured(context))
            const SizedBox(width: SoliplexSpacing.s2),
          Tooltip(
            message: 'Has quizzes',
            child: Icon(
              Icons.quiz,
              size: 20,
              color: theme.colorScheme.primary,
            ),
          ),
        ],
      ],
    );
  }
}
