import 'dart:async';

import 'package:flutter/material.dart';

/// Controls visibility of a scroll-to-bottom button.
///
/// Shows after a short delay when user scrolls up, auto-hides after
/// a longer delay of inactivity.
class ScrollToBottomController extends ChangeNotifier {
  static const _appearDelay = Duration(milliseconds: 300);
  static const _autoHideDelay = Duration(seconds: 3);
  static const _nearBottomThreshold = 100.0;

  bool _visible = false;
  Timer? _showTimer;
  Timer? _hideTimer;

  bool get visible => _visible;

  void scheduleAppearance() {
    if (_showTimer?.isActive ?? false) return;
    _showTimer = Timer(_appearDelay, () {
      _visible = true;
      notifyListeners();
      _scheduleAutoHide();
    });
  }

  void hide() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    _visible = false;
    notifyListeners();
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      _visible = false;
      notifyListeners();
    });
  }

  void updateScrollPosition(ScrollController controller) {
    if (!controller.hasClients) return;
    final pos = controller.position;
    final isNearBottom =
        pos.maxScrollExtent - pos.pixels < _nearBottomThreshold;
    if (isNearBottom) {
      hide();
    } else if (!_visible) {
      scheduleAppearance();
    } else {
      _scheduleAutoHide();
    }
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    _hideTimer?.cancel();
    super.dispose();
  }
}

class ScrollToBottomButton extends StatelessWidget {
  const ScrollToBottomButton({
    super.key,
    required this.controller,
    this.onPressed,
  });

  final ScrollToBottomController controller;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return AnimatedOpacity(
          opacity: controller.visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          child: IgnorePointer(
            ignoring: !controller.visible,
            child: FloatingActionButton.small(
              onPressed: onPressed,
              backgroundColor:
                  Theme.of(context).colorScheme.surfaceContainerHighest,
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              child: const Icon(Icons.keyboard_arrow_down, size: 20),
            ),
          ),
        );
      },
    );
  }
}
