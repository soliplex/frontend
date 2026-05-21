import 'package:flutter/material.dart';

import '../../../design/design.dart';

/// Tappable dots indicator for a `PageView`. Each dot maps to one
/// item; tapping a dot calls [onGoTo] with that index.
///
/// Hidden entirely for single-item lists and for lists above
/// [maxVisible] — past that threshold the dots stop being a useful
/// affordance and the consumer should rely on other navigation
/// (chevrons, "N / M" text, swipe).
class PagerDots extends StatelessWidget {
  const PagerDots({
    super.key,
    required this.itemCount,
    required this.currentIndex,
    required this.onGoTo,
    this.maxVisible = 12,
    this.labelForIndex,
  })  : assert(itemCount >= 0, 'itemCount must be non-negative'),
        assert(maxVisible > 0, 'maxVisible must be positive'),
        assert(
          itemCount == 0 || (currentIndex >= 0 && currentIndex < itemCount),
          'currentIndex out of range for itemCount',
        );

  final int itemCount;
  final int currentIndex;
  final ValueChanged<int> onGoTo;
  final int maxVisible;

  /// Optional per-dot tooltip text (e.g. filename, page label). When
  /// null the dots render without tooltips.
  final String Function(int index)? labelForIndex;

  @override
  Widget build(BuildContext context) {
    if (itemCount <= 1 || itemCount > maxVisible) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(itemCount, (index) {
        final dot = InkResponse(
          onTap: () => onGoTo(index),
          radius: 16,
          child: Padding(
            padding: const EdgeInsets.all(SoliplexSpacing.s1),
            child: CircleAvatar(
              radius: 4,
              backgroundColor: index == currentIndex
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
            ),
          ),
        );
        final label = labelForIndex?.call(index);
        if (label == null) return dot;
        return Tooltip(message: label, child: dot);
      }),
    );
  }
}
