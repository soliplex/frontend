import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';
import 'agent_runtime_manager.dart';
import 'document_selections.dart';
import 'run_registry.dart';
import 'upload_tracker_registry.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.user_switch_teardown');

/// Tears down a server's in-memory state when a *different* user signs in on it
/// within the same process.
///
/// Persistent device-local state is partitioned by user identity, so a switch
/// needs no teardown there. But four in-memory caches would carry the prior
/// user's state into the new session: [AgentRuntimeManager] caches against the
/// live `ServerConnection`, which re-auth reuses; [RunRegistry] and
/// [UploadTrackerRegistry] key by the stable `serverId`; and [DocumentSelections]
/// holds document filters in a single shared map that is not partitioned by
/// user. Without this the next user would reattach to the prior user's runtime,
/// runs, uploads, and document filters. `MessageExpansions` is a fifth
/// module-owned cache left untouched on purpose: its per-message expand/collapse
/// state is cosmetic, and a cross-user collision would need a shared
/// server-assigned `messageId`.
///
/// Detection keys off each server's `AuthSession.currentUserId` rather than the
/// sign-in call sites: that signal is stable across a token refresh (no
/// teardown), stays set through an `ExpiredSession` (so an expiry followed by a
/// different user still counts as a switch), and reading state instead of
/// intercepting transitions covers every auth path — including the silent
/// sign-in that `ServerManager.restoreServers` performs on launch, which the
/// first effect run records as the baseline without evicting. A `null` identity
/// (signed out, or an opaque non-JWT token) is ignored, so a logout alone tears
/// down nothing; the switch is recognised only when a server's identity moves
/// from one non-null user to a different non-null user.
///
/// This leaves a known gap: a server whose IdP issues opaque access tokens has
/// a `null` identity for *every* user, so a switch between two such users is
/// undetectable here and the next user inherits the prior user's in-memory
/// session. That mirrors how those servers already share one unauthenticated
/// bucket for persistent state (see `AuthSession.currentUserId`); isolating them
/// would need a credential fingerprint the token doesn't carry.
///
/// Owned by [RoomAppModule] alongside `RemovedServerCleanup`.
class UserSwitchTeardown {
  UserSwitchTeardown({
    required ReadonlySignal<Map<String, ServerEntry>> servers,
    required AgentRuntimeManager runtimeManager,
    required RunRegistry registry,
    required UploadTrackerRegistry uploadRegistry,
    required DocumentSelections documentSelections,
  })  : _runtimeManager = runtimeManager,
        _registry = registry,
        _uploadRegistry = uploadRegistry,
        _documentSelections = documentSelections {
    _dispose = effect(() {
      for (final MapEntry(key: serverId, value: entry)
          in servers.value.entries) {
        final identity = entry.auth.currentUserId.value;
        // Opaque-token servers report a null identity for every user, so their
        // switches go undetected here — see the class doc's known-gap note.
        if (identity == null) continue;
        final previous = _lastSeen[serverId];
        _lastSeen[serverId] = identity;
        if (previous != null && previous != identity) {
          _evict(serverId);
        }
      }
    });
  }

  final AgentRuntimeManager _runtimeManager;
  final RunRegistry _registry;
  final UploadTrackerRegistry _uploadRegistry;
  final DocumentSelections _documentSelections;
  // Baseline identity per server. An entry for a removed server is left in
  // place: the map is bounded by servers seen this process, and a stale
  // baseline only ever fires a harmless no-op eviction if that id is re-added,
  // since its caches were already cleared on removal.
  final Map<String, String> _lastSeen = {};
  late final void Function() _dispose;

  void _evict(String serverId) {
    _logger.info(
      'Different user signed in on $serverId; '
      'tearing down the prior in-memory session',
    );
    // Each step is isolated: eviction runs synchronously inside the auth signal
    // write that recorded the switch, so a throw escaping here would strand the
    // remaining caches (leaking the prior user's state) and unwind the sign-in.
    _step(() => _runtimeManager.evictServer(serverId), 'runtime', serverId);
    _step(() => _registry.evictServer(serverId), 'runs', serverId);
    _step(() => _uploadRegistry.evictServer(serverId), 'uploads', serverId);
    _step(() => _documentSelections.clearServer(serverId), 'filters', serverId);
  }

  void _step(void Function() evict, String what, String serverId) {
    try {
      evict();
    } on Object catch (error, stackTrace) {
      _logger.error(
        'Failed to tear down $what for $serverId',
        error: error,
        stackTrace: stackTrace,
        attributes: {'serverId': serverId},
      );
    }
  }

  void dispose() => _dispose();
}
