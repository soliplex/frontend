import 'dart:async';

// Signals reach us through soliplex_agent, which is where the app's
// reactive primitives live; 'AuthException' is hidden because the client
// package exports one of its own that this file uses.
import 'package:soliplex_agent/soliplex_agent.dart' hide AuthException;
import 'package:soliplex_client/soliplex_client.dart'
    show
        ApiException,
        AuthException,
        CancelToken,
        NotFoundException,
        PermissionDeniedException,
        SoliplexApi,
        ThreadLabel;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../auth/server_entry.dart';
import 'lobby_state.dart' show ApiResolver;

final Logger _logger = LogManager.instance.getLogger('soliplex.labels_state');

/// The state of one server's label catalogue.
sealed class Labels {
  const Labels();
}

/// The catalogue is being fetched; nothing is on screen yet.
final class LabelsLoading extends Labels {
  const LabelsLoading();
}

/// The catalogue has arrived.
final class LabelsLoaded extends Labels {
  LabelsLoaded(List<ThreadLabel> labels) : labels = List.unmodifiable(labels);
  final List<ThreadLabel> labels;
}

/// The catalogue could not be loaded.
final class LabelsFailed extends Labels {
  const LabelsFailed(this.error);
  final Object error;
}

/// The server has no label catalogue.
///
/// Distinct from [LabelsFailed] because there is nothing to retry: the
/// server simply predates the feature, and offering a retry that will
/// 404 forever reads as a bug.
final class LabelsUnsupported extends Labels {
  const LabelsUnsupported();
}

/// Loads and curates one server's label catalogue.
///
/// Reading is open to anyone — a user has to know the catalogue to
/// attach anything from it — while creating, renaming, recolouring and
/// deleting require administrator access. This holds no opinion about
/// who is allowed what: [LobbyState.isLabelAdmin] decides what the UI
/// paints, and the server refuses anything it should not honour.
class LabelsState {
  LabelsState({
    required ServerEntry? Function(String serverId) entryResolver,
    ApiResolver? apiResolver,
  })  : _entryResolver = entryResolver,
        _apiResolver = apiResolver ?? ((entry) => entry.connection.api);

  final ServerEntry? Function(String serverId) _entryResolver;
  final ApiResolver _apiResolver;

  final Signal<Labels> _labels = Signal(const LabelsLoading());
  ReadonlySignal<Labels> get labels => _labels;

  /// Set while a create/update/delete is in flight, so the tab can
  /// disable its controls without blanking the list.
  final Signal<bool> _busy = Signal(false);
  ReadonlySignal<bool> get busy => _busy;

  String? _serverId;
  CancelToken? _token;
  bool _disposed = false;

  /// Which server's catalogue is loaded, or `null` when none is selected.
  String? get serverId => _serverId;

  /// The catalogue as a flat list, or empty in every other state.
  ///
  /// For callers that only need the names — the `@label` autocomplete,
  /// the properties dialog — and have nothing useful to show for a
  /// failure anyway.
  List<ThreadLabel> get current {
    final value = _labels.value;
    return value is LabelsLoaded ? value.labels : const [];
  }

  /// Points the catalogue at [serverId] and loads it.
  ///
  /// A repeat call for the same server is a no-op, so rebuilds that
  /// re-emit the current selection do not refetch.
  void setServer(String? serverId) {
    if (serverId == _serverId) return;
    _serverId = serverId;
    _cancelInFlight();

    if (serverId == null) {
      _labels.value = LabelsLoaded(const []);
      return;
    }

    _labels.value = const LabelsLoading();
    unawaited(refresh());
  }

  /// Refetches the catalogue.
  Future<void> refresh() async {
    final serverId = _serverId;
    if (serverId == null) return;

    final entry = _entryResolver(serverId);
    if (entry == null) {
      _labels.value = LabelsLoaded(const []);
      return;
    }

    final token = CancelToken();
    _cancelInFlight();
    _token = token;

    try {
      final labels = await _apiResolver(entry).getLabels(cancelToken: token);

      // Bail on anything that moved underneath the request: a cancel, a
      // dispose, or a server switch. Writing here would show one
      // server's catalogue under another's name.
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;
      _labels.value = LabelsLoaded(labels);
    } on Object catch (error, st) {
      if (token.isCancelled || _disposed || serverId != _serverId) return;
      _token = null;

      if (error is NotFoundException) {
        _labels.value = const LabelsUnsupported();
        return;
      }

      if (error is AuthException) {
        entry.auth.markSessionExpired();
        _labels.value = LabelsFailed(error);
        return;
      }

      _logger.error(
        'Failed to fetch labels for $serverId',
        error: error,
        stackTrace: st,
      );
      _labels.value = LabelsFailed(error);
    }
  }

  /// Creates a label, folding it into the held catalogue.
  ///
  /// Returns null on success, or a human-readable reason on failure —
  /// the caller is a dialog, which shows it inline rather than throwing
  /// the user back to the list.
  Future<String?> create({required String name, String? color}) {
    return _mutate((api) async {
      final created = await api.createLabel(name: name, color: color);
      _fold([...current, created]);
    });
  }

  /// Renames and/or recolours a label, folding the result back in.
  Future<String?> update(int labelId, {String? name, String? color}) {
    return _mutate((api) async {
      final updated = await api.updateLabel(labelId, name: name, color: color);
      _fold([
        for (final label in current)
          if (label.id == labelId) updated else label,
      ]);
    });
  }

  /// Deletes a label and drops it from the held catalogue.
  Future<String?> delete(int labelId) {
    return _mutate((api) async {
      await api.deleteLabel(labelId);
      _fold([
        for (final label in current)
          if (label.id != labelId) label,
      ]);
    });
  }

  /// Runs a mutation, returning null on success or a reason on failure.
  ///
  /// The result is folded into the held list by the caller rather than
  /// refetched: the backend commits after responding, so a refetch
  /// issued immediately can still return the pre-write catalogue.
  Future<String?> _mutate(Future<void> Function(SoliplexApi api) body) async {
    final serverId = _serverId;
    if (serverId == null) return 'No server selected';

    final entry = _entryResolver(serverId);
    if (entry == null) return 'No server selected';

    _busy.value = true;
    try {
      await body(_apiResolver(entry));
      return null;
    } on Object catch (error, st) {
      if (_disposed) return null;
      _logger.error(
        'Label operation failed for $serverId',
        error: error,
        stackTrace: st,
      );
      return _reason(error);
    } finally {
      if (!_disposed) _busy.value = false;
    }
  }

  /// A message worth showing a person, rather than an exception dump.
  String _reason(Object error) {
    // 409 is the one failure a user can actually fix, and there is no
    // dedicated exception type for it — the client package treats its
    // hierarchy as off limits — so it is recognised by status here.
    if (error is ApiException && error.statusCode == 409) {
      return 'A label with that name already exists.';
    }
    if (error is NotFoundException) {
      return 'That label no longer exists.';
    }
    if (error is PermissionDeniedException) {
      // Reachable despite the read-only tab: an administrator can be
      // demoted while the page is open, and the server is the authority.
      return 'Only administrators can change labels.';
    }
    if (error is AuthException) {
      return 'You are not signed in.';
    }
    return 'Could not save the label. Please try again.';
  }

  void _fold(List<ThreadLabel> labels) {
    if (_disposed) return;
    final sorted = [...labels]..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
    _labels.value = LabelsLoaded(sorted);
  }

  void _cancelInFlight() {
    _token?.cancel('superseded');
    _token = null;
  }

  void dispose() {
    _disposed = true;
    _cancelInFlight();
  }
}
