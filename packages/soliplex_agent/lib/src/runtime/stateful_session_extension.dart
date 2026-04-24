import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/src/runtime/session_extension.dart';

/// Marker interface for extensions that expose a type-erased reactive state
/// signal. Used by `SessionCoordinator.statefulObservations` to enumerate
/// stateful extensions without knowing concrete type parameters.
abstract interface class HasStatefulObservation {
  ReadonlySignal<Object?> get stateSignalAsObject;
}

/// Adds a single typed reactive-state signal to a [SessionExtension].
///
/// Call [setInitialState] in the constructor before [onAttach] runs.
/// Read [state] / write [state] to drive the signal. Dispose is handled
/// automatically — override [onDispose] and call `super.onDispose()` to
/// chain cleanup.
///
/// ```dart
/// class MyExtension extends SessionExtension
///     with StatefulSessionExtension<MySnapshot> {
///   MyExtension() {
///     setInitialState(const MySnapshot());
///   }
///
///   @override
///   String get namespace => 'my_extension';
///
///   @override
///   Future<void> onAttach(AgentSession session) async {
///     // subscribe to session signals here
///   }
///
///   @override
///   List<ClientTool> get tools => const [];
///
///   @override
///   void onDispose() {
///     // clean up subscriptions
///     super.onDispose(); // disposes the state signal
///   }
/// }
/// ```
mixin StatefulSessionExtension<T> on SessionExtension
    implements HasStatefulObservation {
  Signal<T>? _stateSignal;
  ReadonlySignal<Object?>? _objectSignal;

  /// Initialises the backing signal. Must be called in the constructor.
  void setInitialState(T initial) {
    _stateSignal = signal(initial);
  }

  /// Typed read-only view of the state signal.
  ReadonlySignal<T> get stateSignal {
    assert(_stateSignal != null, 'Call setInitialState() in the constructor');
    return _stateSignal!.readonly();
  }

  /// Current state value.
  T get state => _stateSignal!.value;

  /// Replaces the current state, notifying all subscribers.
  set state(T value) => _stateSignal!.value = value;

  /// Type-erased view of [stateSignal] for use by `SessionCoordinator`.
  ///
  /// Backed by a `computed` signal to avoid unsafe generic casts at runtime.
  @override
  ReadonlySignal<Object?> get stateSignalAsObject {
    return _objectSignal ??= computed<Object?>(() => _stateSignal!.value);
  }

  @override
  void onDispose() {
    _objectSignal?.dispose();
    _objectSignal = null;
    _stateSignal?.dispose();
    _stateSignal = null;
  }
}
