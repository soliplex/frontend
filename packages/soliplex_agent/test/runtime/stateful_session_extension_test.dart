import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/runtime/stateful_session_extension.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Concrete implementation under test
// ---------------------------------------------------------------------------

class _CounterExtension extends SessionExtension
    with StatefulSessionExtension<int> {
  _CounterExtension([int initial = 0]) {
    setInitialState(initial);
  }

  @override
  String get namespace => 'counter';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() => super.onDispose();
}

class _NullableExtension extends SessionExtension
    with StatefulSessionExtension<String?> {
  _NullableExtension() {
    setInitialState(null);
  }

  @override
  String get namespace => 'nullable';

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() => super.onDispose();
}

void main() {
  group('StatefulSessionExtension', () {
    group('initial state', () {
      test('stateSignal reflects initial value', () {
        final ext = _CounterExtension(7);
        expect(ext.stateSignal.value, 7);
      });

      test('state getter returns initial value', () {
        final ext = _CounterExtension(42);
        expect(ext.state, 42);
      });

      test('initial state can be null for nullable type', () {
        final ext = _NullableExtension();
        expect(ext.state, isNull);
      });
    });

    group('state read/write', () {
      test('state setter updates value', () {
        final ext = _CounterExtension(0);
        ext.state = 5;
        expect(ext.state, 5);
      });

      test('stateSignal reflects state setter update', () {
        final ext = _CounterExtension(0);
        ext.state = 99;
        expect(ext.stateSignal.value, 99);
      });

      test('state setter notifies subscribers', () {
        final ext = _CounterExtension(0);
        final received = <int>[];
        ext.stateSignal.subscribe((v) => received.add(v));

        ext.state = 1;
        ext.state = 2;

        expect(received, containsAll([1, 2]));
      });
    });

    group('stateSignalAsObject', () {
      test('returns type-erased signal reflecting current state', () {
        final ext = _CounterExtension(10);
        expect(ext.stateSignalAsObject.value, 10);
      });

      test('type-erased signal tracks state changes', () {
        final ext = _CounterExtension(0);
        final objectSig = ext.stateSignalAsObject;

        ext.state = 77;

        expect(objectSig.value, 77);
      });

      test('returns same instance on repeated calls', () {
        final ext = _CounterExtension(0);
        final sig1 = ext.stateSignalAsObject;
        final sig2 = ext.stateSignalAsObject;
        expect(identical(sig1, sig2), isTrue);
      });
    });

    group('onDispose', () {
      test('cleans up without error', () {
        final ext = _CounterExtension(0);
        expect(() => ext.onDispose(), returnsNormally);
      });

      test('calling onDispose twice does not throw', () {
        final ext = _CounterExtension(0);
        ext.onDispose();
        expect(() => ext.onDispose(), returnsNormally);
      });
    });

    group('implements HasStatefulObservation', () {
      test('extension satisfies HasStatefulObservation', () {
        final ext = _CounterExtension(0);
        expect(ext, isA<HasStatefulObservation>());
      });
    });
  });
}
