import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../core/ui/confirm_dialog.dart';
import '../../../core/ui/menu_row.dart';
import '../auth_providers.dart';
import '../auth_tokens.dart';
import '../server_entry.dart';
import '../server_logout.dart';
import '../server_manager.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.server_sign_out_control');

/// A server row's sign-out and remove action. Shows the caller's idle action,
/// a spinner in its place while the action runs, and an error button after a
/// sign-out fails. The server is kept when a sign-out fails (see
/// [logoutServer]).
class ServerSignOutControl extends ConsumerStatefulWidget {
  const ServerSignOutControl({
    super.key,
    required this.entry,
    required this.serverManager,
    required this.idleBuilder,
  });

  final ServerEntry entry;
  final ServerManager serverManager;

  /// Builds the idle action. [signOut] signs out and keeps the server;
  /// [remove] confirms, then removes (signing out first if it holds a session).
  final Widget Function(
    BuildContext context, {
    required VoidCallback signOut,
    required VoidCallback remove,
  }) idleBuilder;

  @override
  ConsumerState<ServerSignOutControl> createState() =>
      _ServerSignOutControlState();
}

/// A failed sign-out: the sentence to show, whether it was part of a removal,
/// and the session it was attempted on.
typedef _Failure = ({String message, bool removing, SessionState session});

class _ServerSignOutControlState extends ConsumerState<ServerSignOutControl> {
  bool _busy = false;
  _Failure? _failure;

  void _signOut() => _run(remove: false);

  Future<void> _remove() async {
    final entry = widget.entry;
    final signsOut = entry.hasSession;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove server?',
      message: signsOut
          ? "You'll be signed out of '${entry.displayName}' and it will be "
              "removed. You'll need to add it again to reconnect."
          : "Remove '${entry.displayName}'? "
              "You'll need to add it again to reconnect.",
      confirmLabel: 'Remove',
      isDestructive: true,
    );
    if (!confirmed || !mounted) return;
    await _run(remove: true);
  }

  Future<void> _run({required bool remove}) async {
    final entry = widget.entry;
    try {
      setState(() {
        _busy = true;
        _failure = null;
      });
      await logoutServer(
        entry: entry,
        serverManager: widget.serverManager,
        remove: remove,
        authFlow: ref.read(authFlowProvider),
        probeClient: ref.read(probeClientProvider),
        web: kIsWeb,
      );
    } catch (e, st) {
      // error: e is safe: what logoutServer throws is the discovery errors
      // (hosts, public URLs, status codes) and the fixed-text AuthException
      // from `NativeAuthFlow.endSession` — never a token (CLAUDE.md,
      // "Logging").
      _logger.warning(
        remove ? 'Sign-out failed; server kept' : 'Sign-out failed',
        error: e,
        stackTrace: st,
        attributes: {'serverId': entry.serverId},
      );
      // A failed logoutServer leaves local state untouched, so this is the
      // session the failure belongs to.
      final session = entry.auth.session.value;
      if (mounted && session is! NoSession) {
        setState(() => _failure = (
              message: describeLogoutFailure(e),
              removing: remove,
              session: session,
            ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.entry.auth.session.watch(context);
    if (_busy) {
      // A disabled IconButton sizes itself like the idle action it replaces
      // on every platform's visual density.
      return const IconButton(
        onPressed: null,
        tooltip: 'Signing out',
        icon: SizedBox.square(
          dimension: SoliplexSpacing.s6,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final failure = _failure;
    // A failure is recorded against the session it failed on and shows only
    // while that object is current: every session change installs a
    // different object, so any later change, a token refresh included,
    // retires it. None is recorded on NoSession, deliberately: the server is
    // already signed out locally. Every failure is logged.
    if (failure != null && identical(session, failure.session)) {
      return _ErrorButton(
        failure: failure,
        onRetry: () => _run(remove: failure.removing),
        onRemove: () =>
            widget.serverManager.removeServer(widget.entry.serverId),
      );
    }
    return widget.idleBuilder(context, signOut: _signOut, remove: _remove);
  }
}

/// The actions on the error menu (see [_ErrorButton]).
enum _ErrorAction { retry, showDetail, remove }

/// Replaces the idle action after a failed sign-out: a red error icon that
/// opens a menu with **Try again** / **Show error detail** / **Remove
/// server**. The icon tooltip carries the message for a desktop hover; "Show
/// error detail" surfaces it for a touch user. "Remove server" is the escape
/// hatch for a sign-out that keeps failing: it removes the server without
/// signing out again.
class _ErrorButton extends StatelessWidget {
  const _ErrorButton({
    required this.failure,
    required this.onRetry,
    required this.onRemove,
  });

  final _Failure failure;
  final VoidCallback onRetry;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ErrorAction>(
      icon: Icon(
        Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
      ),
      tooltip: failure.message,
      onSelected: (action) {
        switch (action) {
          case _ErrorAction.retry:
            onRetry();
          case _ErrorAction.showDetail:
            _showDetail(context);
          case _ErrorAction.remove:
            onRemove();
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: _ErrorAction.retry,
          child: MenuRow(icon: Icons.refresh, label: 'Try again'),
        ),
        PopupMenuItem(
          value: _ErrorAction.showDetail,
          child: MenuRow(icon: Icons.info_outline, label: 'Show error detail'),
        ),
        PopupMenuItem(
          value: _ErrorAction.remove,
          child: MenuRow(
            icon: Icons.delete_outline,
            label: 'Remove server',
            destructive: true,
          ),
        ),
      ],
    );
  }

  Future<void> _showDetail(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          failure.removing ? 'Server kept — sign-out failed' : 'Log out failed',
        ),
        content: SelectableText(failure.message),
        actions: [
          SoliplexButton.text(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}
