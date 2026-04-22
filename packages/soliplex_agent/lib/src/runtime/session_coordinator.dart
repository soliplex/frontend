import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/runtime/agent_session.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';
import 'package:soliplex_agent/src/runtime/stateful_session_extension.dart';
import 'package:soliplex_agent/src/tools/tool_registry.dart';

/// Manages the lifecycle of a set of [SessionExtension]s for one
/// [AgentSession].
///
/// Responsibilities:
/// - **Namespace validation** — rejects duplicate non-empty namespaces.
/// - **Priority-ordered attach** — [attachAll] sorts by descending priority.
/// - **Reverse-order dispose** — [disposeAll] tears down in reverse attach
///   order.
/// - **Type-based lookup** — [getExtension] mirrors
///   [AgentSession.getExtension].
/// - **Stateful observations** — [statefulObservations] enumerates stateful
///   extensions, yielding `(namespace, signal)` pairs for reactive state
///   consumers that don't need to know the concrete extension types.
class SessionCoordinator {
  SessionCoordinator(List<SessionExtension> extensions)
      : _extensions = List.of(extensions) {
    _validateNamespaces();
  }

  final List<SessionExtension> _extensions;
  List<SessionExtension>? _attachOrder;
  bool _disposed = false;

  /// All tools contributed by all extensions.
  List<ClientTool> get tools => _extensions.expand((e) => e.tools).toList();

  /// Attaches all extensions to [session] in descending priority order.
  Future<void> attachAll(AgentSession session) async {
    final ordered = List.of(_extensions)
      ..sort((a, b) => b.priority.compareTo(a.priority));
    _attachOrder = ordered;
    for (final ext in ordered) {
      await ext.onAttach(session);
    }
  }

  /// Disposes all extensions in reverse attach order. Idempotent.
  void disposeAll() {
    if (_disposed) return;
    _disposed = true;
    final order = _attachOrder ?? _extensions;
    for (final ext in order.reversed) {
      ext.onDispose();
    }
  }

  /// Returns the first extension of type [T], or `null` if none is registered.
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
      switch (ext) {
        case final HasStatefulObservation stateful:
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
