import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/runtime/stateful_session_extension.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Owns the lifecycle of a set of [SessionExtension]s for one
/// [AgentSession]: validates namespaces at construction, attaches and
/// disposes in order, and exposes lookup plus reactive-state enumeration
/// to consumers that don't know the concrete extension types.
class SessionCoordinator {
  /// Throws [ArgumentError] if any two extensions share a non-empty
  /// namespace.
  SessionCoordinator(
    List<SessionExtension> extensions, {
    required Logger logger,
  })  : _extensions = List.of(extensions),
        _logger = logger {
    _validateNamespaces();
  }

  final List<SessionExtension> _extensions;
  final Logger _logger;
  List<SessionExtension>? _attachOrder;
  bool _disposed = false;

  List<ClientTool> get tools => _extensions.expand((e) => e.tools).toList();

  /// Attaches all extensions to [session] in descending priority order.
  ///
  /// On exception, partially-attached extensions are not auto-disposed
  /// here; the caller is responsible for invoking [disposeAll] (in
  /// production this happens via [AgentSession.dispose] from the
  /// spawn-path's cleanup in `AgentRuntime.spawn`).
  Future<void> attachAll(AgentSession session) async {
    final ordered = List.of(_extensions)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    _attachOrder = ordered;
    for (final ext in ordered) {
      await ext.onAttach(session);
    }
  }

  /// Disposes all extensions in reverse of [attachAll]'s priority order,
  /// or in reverse registration order if [attachAll] never ran.
  /// Idempotent and terminal: a throwing `onDispose` is logged per
  /// extension and does not propagate — every registered extension gets
  /// its dispose call.
  void disposeAll() {
    if (_disposed) return;
    _disposed = true;
    final order = _attachOrder ?? _extensions;
    for (final ext in order.reversed) {
      try {
        ext.onDispose();
      } on Object catch (e, st) {
        _logger.error(
          'SessionExtension "${ext.namespace}" onDispose threw',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  /// Returns the first extension of type [T] in registration order, or
  /// `null` if none is registered.
  ///
  /// Uniqueness is enforced by namespace, not by type: two extensions of
  /// the same type with different namespaces are both legal, and this
  /// lookup returns the first-registered one. Prefer namespace-based
  /// discovery when unambiguous lookup matters.
  T? getExtension<T extends SessionExtension>() {
    for (final ext in _extensions) {
      if (ext is T) return ext;
    }
    return null;
  }

  /// Yields `(namespace, signal)` for every [StatefulSessionExtension] with a
  /// non-empty namespace, in registration order.
  ///
  /// Consumers can iterate this to observe all reactive extension state
  /// without importing concrete extension types.
  Iterable<(String, ReadonlySignal<Object?>)> statefulObservations() sync* {
    for (final ext in _extensions) {
      final ns = ext.namespace;
      if (ns.isEmpty) continue;
      if (ext case final HasStatefulObservation stateful) {
        yield (ns, stateful.stateSignalAsObject);
      }
    }
  }

  void _validateNamespaces() {
    final seen = <String>{};
    for (final ext in _extensions) {
      final ns = ext.namespace;
      if (ns.isEmpty) continue;
      if (!seen.add(ns)) {
        throw ArgumentError(
          'Duplicate SessionExtension namespace "$ns". '
          'Each named extension must have a unique namespace.',
        );
      }
    }
  }
}
