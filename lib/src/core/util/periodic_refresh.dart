import 'dart:async';

import 'package:flutter/widgets.dart';

/// How often the lobby and the room rail re-fetch a server's room list, so a
/// room created or removed on the server appears without a reload.
const roomListRefreshInterval = Duration(seconds: 30);

/// Calls [onRefresh] every [interval] while the app is visible, and once each
/// time it becomes visible again (on the web, when the tab is shown).
///
/// Holds no liveness guard of its own: the owner calls [dispose] from its own
/// dispose, or [onRefresh] keeps firing.
class PeriodicRefresh with WidgetsBindingObserver {
  PeriodicRefresh({required this.interval, required this.onRefresh});

  final Duration interval;
  final VoidCallback onRefresh;

  Timer? _timer;
  bool _visible = true;

  void start() {
    if (_timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(interval, (_) {
      if (_visible) onRefresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_timer == null) return;
    // 'inactive' is a focus loss with the app still on screen (a blurred
    // browser window), so it counts as visible.
    final visible = state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (visible && !_visible) onRefresh();
    _visible = visible;
  }

  void dispose() {
    final timer = _timer;
    if (timer == null) return;
    timer.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }
}
