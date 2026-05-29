import 'dart:async';

import 'package:flutter/material.dart';

import 'inactivity_dialog.dart';
import 'inactivity_monitor.dart';

/// Renders [child] and pushes / removes [InactivityDialog] in response
/// to [InactivityMonitor.warningVisible].
///
/// Mounted from `MaterialApp.router`'s builder so the host's
/// [BuildContext] sits inside the root navigator. Reacting via signal
/// subscription (instead of [Watch] in build) keeps the imperative
/// [Navigator] calls outside the build phase.
class InactivityDialogHost extends StatefulWidget {
  const InactivityDialogHost({
    super.key,
    required this.monitor,
    required this.navigatorKey,
    required this.child,
  });

  final InactivityMonitor monitor;

  /// Key for the navigator the dialog is pushed onto. The host itself
  /// sits in `MaterialApp.router`'s `builder` slot, which is *above*
  /// the navigator in the widget tree, so `Navigator.of(context)`
  /// can't find one from the host's own context. The key gives the
  /// host a direct handle to the navigator's state.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<InactivityDialogHost> createState() => _InactivityDialogHostState();
}

class _InactivityDialogHostState extends State<InactivityDialogHost> {
  Route<void>? _dialogRoute;
  void Function()? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription =
        widget.monitor.warningVisible.subscribe(_onWarningVisibleChanged);
  }

  @override
  void dispose() {
    _subscription?.call();
    _subscription = null;
    super.dispose();
  }

  void _onWarningVisibleChanged(bool visible) {
    if (!mounted) return;
    // Microtask defers past the current signal-update batch but still
    // runs before the next frame, so we don't depend on a frame being
    // scheduled by some other code path before the dialog appears.
    scheduleMicrotask(() {
      if (!mounted) return;
      if (visible && _dialogRoute == null) {
        _showDialog();
      } else if (!visible && _dialogRoute != null) {
        _dismissDialog();
      }
    });
  }

  void _showDialog() {
    final nav = widget.navigatorKey.currentState;
    if (nav == null) return;
    final route = DialogRoute<void>(
      context: nav.context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => InactivityDialog(
        graceDeadline: widget.monitor.graceDeadline,
        onExtend: widget.monitor.extendSession,
        onLogout: widget.monitor.logoutNow,
      ),
    );
    _dialogRoute = route;
    nav.push(route);
  }

  void _dismissDialog() {
    final route = _dialogRoute;
    _dialogRoute = null;
    if (route == null || !route.isActive) return;
    widget.navigatorKey.currentState?.removeRoute(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
