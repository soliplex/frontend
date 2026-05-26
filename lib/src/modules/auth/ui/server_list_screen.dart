import 'dart:developer' as dev;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:soliplex_agent/soliplex_agent.dart'
    show fetchOidcDiscoveryDocument;
import 'package:soliplex_client/soliplex_client.dart' show SoliplexException;

import '../../../core/routes.dart';
import '../auth_providers.dart';
import '../auth_tokens.dart';
import '../server_entry.dart';
import '../server_manager.dart';
import 'package:soliplex_design/soliplex_design.dart';

class ServerListScreen extends ConsumerStatefulWidget {
  const ServerListScreen({super.key, required this.serverManager});

  final ServerManager serverManager;

  @override
  ConsumerState<ServerListScreen> createState() => _ServerListScreenState();
}

class _ServerListScreenState extends ConsumerState<ServerListScreen> {
  late final void Function() _unsubscribe;

  // Per-entry in-flight tracking. The setState that removes a serverId
  // from _loggingOut in the `finally` of the button handler is also
  // what triggers the row connected→disconnected rebuild — the
  // existing `_servers` subscription only fires on structural
  // (add/remove) changes, not on inner per-entry session changes.
  final Set<String> _loggingOut = {};
  final Map<String, String> _logoutErrors = {};

  @override
  void initState() {
    super.initState();
    _unsubscribe = widget.serverManager.servers.subscribe((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final servers = widget.serverManager.servers.value;
    final connected = servers.values.where((e) => e.isConnected).toList();
    final disconnected = servers.values.where((e) => !e.isConnected).toList();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Servers'),
        automaticallyImplyLeading: false,
        actions: [
          TextButton(
            onPressed: () => context.go(AppRoutes.home),
            child: const Text('Home'),
          ),
          if (connected.isNotEmpty)
            TextButton(
              onPressed: () => context.go(AppRoutes.lobby),
              child: const Text('Lobby'),
            ),
        ],
      ),
      body: ListView(
        children: [
          if (connected.isNotEmpty) ...[
            _sectionHeader(theme, 'Connected (${connected.length})'),
            for (final entry in connected) _connectedTile(theme, entry),
          ],
          if (disconnected.isNotEmpty) ...[
            _sectionHeader(theme, 'Disconnected (${disconnected.length})'),
            for (final entry in disconnected) _disconnectedTile(theme, entry),
          ],
        ],
      ),
    );
  }

  Widget _sectionHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s4, SoliplexSpacing.s4,
          SoliplexSpacing.s4, SoliplexSpacing.s1),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _connectedTile(ThemeData theme, ServerEntry entry) {
    final inFlight = _loggingOut.contains(entry.serverId);
    final error = _logoutErrors[entry.serverId];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          title: Text(formatServerUrl(entry.serverUrl)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (entry.requiresAuth)
                TextButton(
                  onPressed: inFlight
                      ? null
                      : () => _runLogout(entry, removeAfter: false),
                  child: inFlight
                      ? const SizedBox(
                          width: SoliplexSpacing.s4,
                          height: SoliplexSpacing.s4,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Log out'),
                ),
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: theme.colorScheme.error,
                ),
                onPressed: inFlight
                    ? null
                    : () => _runLogout(entry, removeAfter: true),
              ),
            ],
          ),
          onTap: inFlight ? null : () => context.go(AppRoutes.lobby),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SoliplexSpacing.s4,
              0,
              SoliplexSpacing.s4,
              SoliplexSpacing.s2,
            ),
            child: Text(
              'Log out failed: $error',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
      ],
    );
  }

  Widget _disconnectedTile(ThemeData theme, ServerEntry entry) {
    return ListTile(
      title: Text(formatServerUrl(entry.serverUrl)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton(
            onPressed: () => context.go(
              AppRoutes.homeWithUrl(entry.serverUrl.toString()),
            ),
            child: const Text('Sign in'),
          ),
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            onPressed: () => widget.serverManager.removeServer(entry.serverId),
          ),
        ],
      ),
      onTap: () => context.go(
        AppRoutes.homeWithUrl(entry.serverUrl.toString()),
      ),
    );
  }

  Future<void> _runLogout(ServerEntry entry,
      {required bool removeAfter}) async {
    setState(() {
      _loggingOut.add(entry.serverId);
      _logoutErrors.remove(entry.serverId);
    });
    try {
      await _logout(entry);
      if (removeAfter) {
        widget.serverManager.removeServer(entry.serverId);
      }
    } catch (e, st) {
      dev.log(
        removeAfter ? 'Logout failed; row preserved' : 'Logout failed',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() => _logoutErrors[entry.serverId] = _friendlyLogoutError(e));
      }
    } finally {
      if (mounted) {
        setState(() => _loggingOut.remove(entry.serverId));
      }
    }
  }

  /// Strips internal exception type names from common logout errors so
  /// "Log out failed: $msg" reads as a sentence rather than a stack
  /// trace. The original exception is logged elsewhere; this is
  /// render-only.
  String _friendlyLogoutError(Object e) {
    String raw;
    if (e is PlatformException) {
      raw = e.message ?? e.code;
    } else if (e is SoliplexException) {
      raw = e.message;
    } else if (e is Exception) {
      final s = e.toString();
      raw = s.startsWith('Exception: ') ? s.substring(11) : s;
    } else {
      // Unknown throwable (e.g. a stray Error from a programmer bug).
      // Render a generic one-liner rather than risk dumping a raw
      // toString into the inline error slot.
      raw = 'Sign-out failed. Please try again.';
    }
    const limit = 200;
    return raw.length > limit ? '${raw.substring(0, limit - 1)}…' : raw;
  }

  // Ordering of `entry.auth.logout()` relative to `authFlow.endSession`
  // is platform-conditional.
  //
  // Native (iOS/macOS/Android): `endSession` opens a system browser sheet
  // via flutter_appauth, the IdP round-trip completes in-process, and
  // control returns to Dart. We clear the local session ONLY after
  // `endSession` returns cleanly. If it throws (user cancel, network,
  // IdP unreachable), the local session stays `ActiveSession` and
  // `_runLogout`'s catch surfaces the error inline. This keeps the
  // invariant "local state matches IdP state."
  //
  // Web: `WebAuthFlow.endSession` is a full-page navigation to the IdP's
  // logout endpoint — the SPA is unloading. There is no in-process
  // signal of IdP completion (the redirect-back is the confirmation,
  // and by then the previous page is gone). If we waited until after
  // the await to clear local, the post-await code would race the unload
  // and likely not persist `NoSession` to storage in time. On
  // restoreServers(), the SPA would pick up a stale `ActiveSession` and
  // the user would appear signed in with dead tokens until the next
  // 401 → refresh → ExpiredSession cycle. So on web we clear local
  // BEFORE navigating, accepting the weaker invariant that if the user
  // dismisses the IdP logout sheet, local will be cleared even though
  // the IdP session is still alive. This drift self-corrects on the
  // next sign-in (the IdP's SSO cookie typically auto-issues fresh
  // tokens for the same user without a prompt).
  //
  // The principled fix for web parity would be a backend "BFF logout"
  // endpoint (mirroring the existing `/api/login/{provider}` BFF
  // sign-in pattern). The frontend would POST to the backend, which
  // calls the IdP's logout server-to-server (no CORS, no full-page
  // navigation), and the await would resolve only when the IdP
  // confirms — matching native semantics.
  Future<void> _logout(ServerEntry entry) async {
    final session = entry.auth.session.value;
    if (session is! ActiveSession) {
      entry.auth.logout();
      return;
    }
    final authFlow = ref.read(authFlowProvider);

    if (kIsWeb) {
      // Web needs the IdP's `end_session_endpoint` (extracted from the
      // discovery document) to navigate to. `WebAuthFlow.endSession`
      // is a full-page navigation, so local state is cleared first per
      // the ordering comment above. A discovery-fetch failure bubbles
      // to `_runLogout` and preserves the local session — the
      // alternative (degrading to `endSessionEndpoint = null`) would
      // clear local while the IdP session stays alive.
      final httpClient = ref.read(probeClientProvider);
      final discovery = await fetchOidcDiscoveryDocument(
        Uri.parse(session.provider.discoveryUrl),
        httpClient,
      );
      entry.auth.logout();
      await authFlow.endSession(
        discoveryUrl: session.provider.discoveryUrl,
        endSessionEndpoint: discovery.endSessionEndpoint?.toString(),
        idToken: session.tokens.idToken ?? '',
        clientId: session.provider.clientId,
      );
      return;
    }

    // Native: `NativeAuthFlow.endSession` re-discovers via
    // `discoveryUrl` through `flutter_appauth`, so the
    // `endSessionEndpoint` argument is unused — don't pay for a
    // pre-fetch.
    await authFlow.endSession(
      discoveryUrl: session.provider.discoveryUrl,
      endSessionEndpoint: null,
      idToken: session.tokens.idToken ?? '',
      clientId: session.provider.clientId,
    );
    entry.auth.logout();
  }
}
