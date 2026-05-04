import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/runtime/stateful_session_extension.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Owns the lifecycle of a set of [SessionExtension]s for one
/// [AgentSession]: dedupes namespaces at construction, attaches and
/// disposes in order, and exposes lookup plus reactive-state enumeration
/// to consumers that don't know the concrete extension types.
class SessionCoordinator {
  /// Constructs a coordinator for [extensions]. Duplicate non-empty
  /// namespaces are dropped at construction (first-registered wins) with
  /// a logged error — keeping a duplicate around runs its `onAttach` /
  /// `onDispose` and contributes its `tools`, which would silently
  /// violate the single-policy invariants extensions are supposed to
  /// enforce. Treat duplicate registration as a flavor configuration bug.
  SessionCoordinator(
    List<SessionExtension> extensions, {
    required Logger logger,
  })  : _extensions = _dedupe(extensions, logger),
        _logger = logger;

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

  static List<SessionExtension> _dedupe(
    List<SessionExtension> extensions,
    Logger logger,
  ) {
    final seen = <String>{};
    final unique = <SessionExtension>[];
    for (final ext in extensions) {
      final ns = ext.namespace;
      if (ns.isEmpty || seen.add(ns)) {
        unique.add(ext);
      } else {
        logger.error(
          'Duplicate SessionExtension namespace "$ns"; dropping '
          '${ext.runtimeType}. First-registered wins. This is a flavor '
          'configuration bug.',
        );
      }
    }
    return unique;
  }
}
