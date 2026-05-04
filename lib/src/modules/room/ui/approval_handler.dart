import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../human_approval_extension.dart';

/// Bridges a [ReadonlySignal] of [ApprovalRequest] to imperative
/// `showDialog` calls. Renders nothing itself; mount anywhere in the tree
/// that stays alive across the dialog's lifetime.
class ApprovalHandler extends StatefulWidget {
  const ApprovalHandler({
    super.key,
    required this.pendingApproval,
    required this.onRespond,
  });

  final ReadonlySignal<ApprovalRequest?> pendingApproval;
  final void Function(ApprovalRequest request, bool approved) onRespond;

  @override
  State<ApprovalHandler> createState() => _ApprovalHandlerState();
}

class _ApprovalHandlerState extends State<ApprovalHandler> {
  void Function()? _unsub;
  ApprovalRequest? _showing;
  Route<bool>? _dialogRoute;

  @override
  void initState() {
    super.initState();
    _unsub = widget.pendingApproval.subscribe(_onChange);
  }

  @override
  void didUpdateWidget(covariant ApprovalHandler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.pendingApproval, widget.pendingApproval)) {
      _unsub?.call();
      _showing = null;
      _dismissDialog();
      _unsub = widget.pendingApproval.subscribe(_onChange);
    }
  }

  void _onChange(ApprovalRequest? request) {
    if (request == null) {
      // Extension cleared the request (cancellation, dispose, supersede).
      // Dismiss the showing dialog so it does not float over the next
      // screen. The awaiting `_show` resumes, hits the identity guard,
      // and skips onRespond.
      _showing = null;
      _dismissDialog();
      return;
    }
    if (identical(request, _showing)) return;
    _dismissDialog();
    _showing = request;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-check identity inside the post-frame callback: a same-frame
      // burst of signal updates can queue stale `_show(request)` calls
      // after `_showing` already moved on.
      if (!mounted) return;
      if (!identical(request, _showing)) return;
      _show(request);
    });
  }

  // removeRoute targets this exact dialog, even if it is mid-pop or no
  // longer the topmost route.
  void _dismissDialog() {
    final route = _dialogRoute;
    _dialogRoute = null;
    if (route != null && route.isActive) {
      route.navigator?.removeRoute(route);
    }
  }

  Future<void> _show(ApprovalRequest request) async {
    final route = DialogRoute<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ApprovalDialog(request: request),
    );
    _dialogRoute = route;
    final approved =
        await Navigator.of(context, rootNavigator: true).push(route);
    if (identical(_dialogRoute, route)) _dialogRoute = null;
    // dispose() leaves the pending request live (see dispose comment);
    // don't synth-deny here.
    if (!mounted) return;
    if (!identical(request, _showing)) return;
    widget.onRespond(request, approved ?? false);
    _showing = null;
  }

  @override
  void dispose() {
    // Remove the orphan dialog so it does not float over the next screen.
    // The pending request is intentionally not denied here — if the user
    // returns to the screen, re-attaching the session re-shows the dialog
    // via the signal.
    _dismissDialog();
    _unsub?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Dialog that prompts the user to approve or deny a pending tool call.
class ApprovalDialog extends StatelessWidget {
  const ApprovalDialog({super.key, required this.request});

  final ApprovalRequest request;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.security, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 8),
          const Text('Tool Approval Required'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.toolName,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(request.rationale, style: theme.textTheme.bodyMedium),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Deny'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Allow'),
        ),
      ],
    );
  }
}
