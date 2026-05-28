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
    required this.child,
  });

  final InactivityMonitor monitor;
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
    if (visible && _dialogRoute == null) {
      _showDialog();
    } else if (!visible && _dialogRoute != null) {
      _dismissDialog();
    }
  }

  void _showDialog() {
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      animationStyle: AnimationStyle.noAnimation,
      builder: (_) => InactivityDialog(
        graceDeadline: widget.monitor.graceDeadline,
        onExtend: widget.monitor.extendSession,
        onLogout: widget.monitor.logoutNow,
      ),
    );
    _dialogRoute = route;
    Navigator.of(context, rootNavigator: true).push(route);
  }

  void _dismissDialog() {
    final route = _dialogRoute;
    _dialogRoute = null;
    if (route == null || !route.isActive) return;
    Navigator.of(context, rootNavigator: true).removeRoute(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
