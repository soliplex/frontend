import 'package:flutter_test/flutter_test.dart';
import 'package:signals_core/signals_core.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/conversation_state_extension.dart';

// ---------------------------------------------------------------------------
// Fake session exposing just the signals the extension needs
// ---------------------------------------------------------------------------

class _FakeSession implements AgentSession {
  final Signal<RunState> _runState = Signal(const IdleState());

  @override
  ReadonlySignal<RunState> get runState => _runState;

  void emit(RunState state) => _runState.value = state;

  @override
  dynamic noSuchMethod(Invocation i) => null;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

const _threadKey = (serverId: 'srv', roomId: 'room', threadId: 'thread');

Conversation _conversation({Map<String, dynamic> aguiState = const {}}) =>
    Conversation(threadId: 'thread', aguiState: aguiState);

RunningState _running(Conversation conv) => RunningState(
      threadKey: _threadKey,
      runId: 'r1',
      conversation: conv,
      streaming: const AwaitingText(),
    );

CompletedState _completed(Conversation conv) => CompletedState(
      threadKey: _threadKey,
      runId: 'r1',
      conversation: conv,
    );

FailedState _failed(Conversation conv) => FailedState(
      threadKey: _threadKey,
      reason: FailureReason.internalError,
      error: 'fail',
      conversation: conv,
    );

void main() {
  group('ConversationStateExtension', () {
    late ConversationStateExtension ext;
    late _FakeSession session;

    setUp(() async {
      ext = ConversationStateExtension();
      session = _FakeSession();
      await ext.onAttach(session);
    });

    tearDown(() => ext.onDispose());

    test('initial state is empty map', () {
      expect(ext.state, isEmpty);
      expect(ext.stateSignal.value, isEmpty);
    });

    test('updates state from RunningState conversation aguiState', () {
      session.emit(_running(_conversation(aguiState: {'key': 'value'})));

      expect(ext.state, {'key': 'value'});
    });

    test('updates state from CompletedState conversation aguiState', () {
      session.emit(_completed(_conversation(aguiState: {'done': true})));

      expect(ext.state, {'done': true});
    });

    test('updates state from FailedState when conversation is present', () {
      session.emit(_failed(_conversation(aguiState: {'err': 1})));

      expect(ext.state, {'err': 1});
    });

    test('does not update state for IdleState', () {
      session.emit(_running(_conversation(aguiState: {'step': 1})));
      session.emit(const IdleState());

      expect(ext.state, {'step': 1});
    });

    test('does not update state when aguiState is unchanged', () {
      final aguiState = {'x': 1};
      session.emit(_running(_conversation(aguiState: aguiState)));

      final snapshot = ext.state;
      session.emit(_running(_conversation(aguiState: aguiState)));

      expect(identical(ext.state, snapshot), isTrue);
    });

    test('stateSignal notifies on change', () {
      final received = <Map<String, dynamic>>[];
      ext.stateSignal.subscribe((v) {
        if (v.isNotEmpty) received.add(v);
      });

      session.emit(_running(_conversation(aguiState: {'a': 1})));
      session.emit(_running(_conversation(aguiState: {'b': 2})));

      expect(received.length, 2);
    });

    test('namespace is conversation_state', () {
      expect(ext.namespace, 'conversation_state');
    });

    test('priority is 20', () {
      expect(ext.priority, 20);
    });

    test('tools is empty', () {
      expect(ext.tools, isEmpty);
    });

    test('onDispose unsubscribes from runState', () {
      ext.onDispose();

      expect(
        () => session.emit(_running(_conversation(aguiState: {'post': 'dispose'}))),
        returnsNormally,
      );
    });
  });
}
