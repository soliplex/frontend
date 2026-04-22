import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/runtime/session_coordinator.dart';
import 'package:soliplex_agent/src/runtime/stateful_session_extension.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Test doubles
// ---------------------------------------------------------------------------

class _FakeExtension extends SessionExtension {
  _FakeExtension({String ns = '', int pri = 0, List<ClientTool> t = const []})
      : _ns = ns,
        _pri = pri,
        _tools = t;

  final String _ns;
  final int _pri;
  final List<ClientTool> _tools;

  int attachCount = 0;
  int disposeCount = 0;
  AgentSession? attachedSession;

  @override
  String get namespace => _ns;

  @override
  int get priority => _pri;

  @override
  Future<void> onAttach(AgentSession session) async {
    attachCount++;
    attachedSession = session;
  }

  @override
  List<ClientTool> get tools => _tools;

  @override
  void onDispose() => disposeCount++;
}

class _StatefulExtension extends SessionExtension
    with StatefulSessionExtension<int> {
  _StatefulExtension(int initial, {String ns = 'stateful', int pri = 0}) {
    setInitialState(initial);
    _ns = ns;
    _pri = pri;
  }

  late final String _ns;
  late final int _pri;

  @override
  String get namespace => _ns;

  @override
  int get priority => _pri;

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() => super.onDispose();
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('SessionCoordinator', () {
    group('namespace validation', () {
      test('accepts empty list', () {
        expect(() => SessionCoordinator(const []), returnsNormally);
      });

      test('accepts unique namespaces', () {
        final a = _FakeExtension(ns: 'a');
        final b = _FakeExtension(ns: 'b');
        expect(() => SessionCoordinator([a, b]), returnsNormally);
      });

      test('accepts multiple extensions with empty namespace', () {
        final a = _FakeExtension(ns: '');
        final b = _FakeExtension(ns: '');
        expect(() => SessionCoordinator([a, b]), returnsNormally);
      });

      test('throws ArgumentError for duplicate non-empty namespace', () {
        final a = _FakeExtension(ns: 'dup');
        final b = _FakeExtension(ns: 'dup');
        expect(
          () => SessionCoordinator([a, b]),
          throwsA(isA<ArgumentError>()),
        );
      });
    });

    group('attachAll', () {
      test('calls onAttach on all extensions', () async {
        final a = _FakeExtension(ns: 'a');
        final b = _FakeExtension(ns: 'b');
        final coordinator = SessionCoordinator([a, b]);

        // We can't easily pass a real AgentSession here, so we verify that
        // attachCount increments (onAttach was called).
        // Use a fake that satisfies the type requirement via noSuchMethod.
        final fakeSession = _FakeAgentSessionStub();
        await coordinator.attachAll(fakeSession);

        expect(a.attachCount, 1);
        expect(b.attachCount, 1);
      });

      test('attaches in descending priority order', () async {
        final order = <int>[];
        final low = _OrderRecordingExtension(ns: 'low', pri: 1, order: order);
        final high = _OrderRecordingExtension(ns: 'high', pri: 10, order: order);
        final mid = _OrderRecordingExtension(ns: 'mid', pri: 5, order: order);

        final coordinator = SessionCoordinator([low, high, mid]);
        await coordinator.attachAll(_FakeAgentSessionStub());

        expect(order, [10, 5, 1]);
      });
    });

    group('disposeAll', () {
      test('calls onDispose on all extensions', () async {
        final a = _FakeExtension(ns: 'a');
        final b = _FakeExtension(ns: 'b');
        final coordinator = SessionCoordinator([a, b]);

        await coordinator.attachAll(_FakeAgentSessionStub());
        coordinator.disposeAll();

        expect(a.disposeCount, 1);
        expect(b.disposeCount, 1);
      });

      test('disposes in reverse attach order', () async {
        final order = <int>[];
        final low = _DisposeOrderExtension(ns: 'low', pri: 1, order: order);
        final high = _DisposeOrderExtension(ns: 'high', pri: 10, order: order);
        final mid = _DisposeOrderExtension(ns: 'mid', pri: 5, order: order);

        final coordinator = SessionCoordinator([low, high, mid]);
        await coordinator.attachAll(_FakeAgentSessionStub());
        coordinator.disposeAll();

        // Attach order was [high(10), mid(5), low(1)]; dispose reverses it.
        expect(order, [1, 5, 10]);
      });

      test('is idempotent — calling twice does not double-dispose', () async {
        final ext = _FakeExtension(ns: 'x');
        final coordinator = SessionCoordinator([ext]);
        await coordinator.attachAll(_FakeAgentSessionStub());

        coordinator.disposeAll();
        coordinator.disposeAll();

        expect(ext.disposeCount, 1);
      });

      test('disposes without prior attachAll (uses registration order)', () {
        final a = _FakeExtension(ns: 'a');
        final b = _FakeExtension(ns: 'b');
        final coordinator = SessionCoordinator([a, b]);

        expect(() => coordinator.disposeAll(), returnsNormally);
        expect(a.disposeCount, 1);
        expect(b.disposeCount, 1);
      });
    });

    group('getExtension', () {
      test('returns matching extension by type', () {
        final ext = _FakeExtension(ns: 'a');
        final coordinator = SessionCoordinator([ext]);

        expect(coordinator.getExtension<_FakeExtension>(), same(ext));
      });

      test('returns null when type not registered', () {
        final coordinator = SessionCoordinator(const []);

        expect(coordinator.getExtension<_FakeExtension>(), isNull);
      });

      test('returns first matching extension when multiple present', () {
        final first = _FakeExtension(ns: 'first');
        final second = _FakeExtension(ns: 'second');
        final coordinator = SessionCoordinator([first, second]);

        expect(coordinator.getExtension<_FakeExtension>(), same(first));
      });
    });

    group('statefulObservations', () {
      test('yields nothing for empty coordinator', () {
        final coordinator = SessionCoordinator(const []);
        expect(coordinator.statefulObservations(), isEmpty);
      });

      test('yields nothing for non-stateful extensions', () {
        final ext = _FakeExtension(ns: 'plain');
        final coordinator = SessionCoordinator([ext]);
        expect(coordinator.statefulObservations(), isEmpty);
      });

      test('skips stateful extension with empty namespace', () {
        final ext = _StatefulExtension(0, ns: '');
        final coordinator = SessionCoordinator([ext]);
        expect(coordinator.statefulObservations(), isEmpty);
      });

      test('yields (namespace, signal) for stateful extension', () {
        final ext = _StatefulExtension(42, ns: 'my_ext');
        final coordinator = SessionCoordinator([ext]);

        final obs = coordinator.statefulObservations().toList();

        expect(obs, hasLength(1));
        expect(obs.first.$1, 'my_ext');
        expect(obs.first.$2.value, 42);
      });

      test('signal in observation reflects state changes', () {
        final ext = _StatefulExtension(0, ns: 'counter');
        final coordinator = SessionCoordinator([ext]);

        final obs = coordinator.statefulObservations().first;
        expect(obs.$2.value, 0);

        ext.state = 99;
        expect(obs.$2.value, 99);
      });

      test('yields one entry per stateful extension with namespace', () {
        final a = _StatefulExtension(1, ns: 'a');
        final b = _StatefulExtension(2, ns: 'b');
        final plain = _FakeExtension(ns: 'plain');
        final coordinator = SessionCoordinator([a, plain, b]);

        final obs = coordinator.statefulObservations().toList();

        expect(obs, hasLength(2));
        expect(obs.map((e) => e.$1), containsAll(['a', 'b']));
      });
    });

    group('tools', () {
      test('returns empty list when no tools contributed', () {
        final coordinator = SessionCoordinator([_FakeExtension()]);
        expect(coordinator.tools, isEmpty);
      });

      test('flattens tools from all extensions', () {
        final tool1 = ClientTool(
          definition: const Tool(name: 'tool_a', description: 'A'),
          executor: (_, __) async => '',
        );
        final tool2 = ClientTool(
          definition: const Tool(name: 'tool_b', description: 'B'),
          executor: (_, __) async => '',
        );
        final a = _FakeExtension(ns: 'a', t: [tool1]);
        final b = _FakeExtension(ns: 'b', t: [tool2]);
        final coordinator = SessionCoordinator([a, b]);

        expect(
          coordinator.tools.map((t) => t.definition.name),
          containsAll(['tool_a', 'tool_b']),
        );
      });
    });
  });
}

// ---------------------------------------------------------------------------
// Additional test doubles
// ---------------------------------------------------------------------------

class _FakeAgentSessionStub implements AgentSession {
  @override
  dynamic noSuchMethod(Invocation i) => null;
}

class _OrderRecordingExtension extends SessionExtension {
  _OrderRecordingExtension({
    required String ns,
    required int pri,
    required this.order,
  })  : _ns = ns,
        _pri = pri;

  final String _ns;
  final int _pri;
  final List<int> order;

  @override
  String get namespace => _ns;

  @override
  int get priority => _pri;

  @override
  Future<void> onAttach(AgentSession session) async => order.add(_pri);

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() {}
}

class _DisposeOrderExtension extends SessionExtension {
  _DisposeOrderExtension({
    required String ns,
    required int pri,
    required this.order,
  })  : _ns = ns,
        _pri = pri;

  final String _ns;
  final int _pri;
  final List<int> order;

  @override
  String get namespace => _ns;

  @override
  int get priority => _pri;

  @override
  Future<void> onAttach(AgentSession session) async {}

  @override
  List<ClientTool> get tools => const [];

  @override
  void onDispose() => order.add(_pri);
}
