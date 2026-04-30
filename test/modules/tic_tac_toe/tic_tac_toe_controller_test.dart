import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_controller.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_state.dart';

import 'fakes.dart';

class _FakeRuntime implements AgentRuntime {
  final ThreadState threadState = ThreadState();
  StateBus get bus => threadState.bus;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #ensureThreadState) {
      return threadState;
    }
    if (invocation.memberName == #spawn) {
      return Future.value(FakeAgentSession());
    }
    return super.noSuchMethod(invocation);
  }
}

class _RecordingRuntime implements AgentRuntime {
  _RecordingRuntime() : threadState = ThreadState();
  final ThreadState threadState;
  StateBus get bus => threadState.bus;
  Map<String, dynamic>? lastStateOverlay;
  String? lastRoomId;
  String? lastThreadId;
  String? lastPrompt;
  late AgentSession sessionToReturn;

  @override
  Future<AgentSession> spawn({
    required String roomId,
    required String prompt,
    String? threadId,
    Duration? timeout,
    bool ephemeral = false,
    bool autoDispose = false,
    AgentSession? parent,
    Map<String, dynamic>? stateOverlay,
  }) async {
    lastRoomId = roomId;
    lastThreadId = threadId;
    lastPrompt = prompt;
    lastStateOverlay = stateOverlay;
    return sessionToReturn;
  }

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #ensureThreadState) {
      return threadState;
    }
    return super.noSuchMethod(i);
  }
}

void main() {
  late _FakeRuntime runtime;
  late TicTacToeController controller;

  setUp(() {
    runtime = _FakeRuntime();
    runtime.bus.setAgentState({
      'game': {
        'id': 'g1',
        'board': List.generate(3, (_) => List.filled(3, null)),
        'moves': <dynamic>[],
        'turn': 'user',
        'winner': null,
        'winning_line': null,
      },
    });
    controller = TicTacToeController(
      threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
      runtime: runtime,
    );
  });

  tearDown(() => controller.dispose());

  test('clickCell stages pending', () {
    controller.clickCell(1, 1);
    expect(controller.state.value.pending, const Cell(1, 1));
  });

  test('clickCell on staged cell unstages (toggle)', () {
    controller.clickCell(1, 1);
    controller.clickCell(1, 1);
    expect(controller.state.value.pending, isNull);
  });

  test('clickCell on different cell replaces pending', () {
    controller.clickCell(1, 1);
    controller.clickCell(2, 2);
    expect(controller.state.value.pending, const Cell(2, 2));
  });

  test('clickCell ignored when game is null', () {
    runtime.bus.setAgentState({});
    controller.clickCell(0, 0);
    expect(controller.state.value.pending, isNull);
  });

  test('clickCell ignored when cell occupied', () {
    runtime.bus.setAgentState({
      'game': {
        'id': 'g1',
        'board': [
          ['X', null, null],
          [null, null, null],
          [null, null, null],
        ],
        'moves': <dynamic>[],
        'turn': 'user',
        'winner': null,
        'winning_line': null,
      },
    });
    controller.clickCell(0, 0);
    expect(controller.state.value.pending, isNull);
  });

  test('clickUndo with pending clears pending only (no server)', () {
    controller.clickCell(1, 1);
    controller.clickUndo();
    expect(controller.state.value.pending, isNull);
    expect(controller.state.value.redoStack, isEmpty);
  });

  group('committed undo / redo', () {
    test('undo with no pending and last mover agent pops a turn-pair', () {
      runtime.bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': [
            ['X', null, null],
            ['O', null, null],
            [null, null, null],
          ],
          'moves': [
            {'player': 'user', 'row': 0, 'col': 0, 'mark': 'X'},
            {'player': 'agent', 'row': 1, 'col': 0, 'mark': 'O'},
          ],
          'turn': 'user',
          'winner': null,
          'winning_line': null,
        },
      });
      controller.clickUndo();
      expect(controller.state.value.redoStack, hasLength(1));
      expect(controller.state.value.redoStack.first.user, const Cell(0, 0));
      expect(controller.state.value.redoStack.first.agent, const Cell(1, 0));
      expect(controller.lastDispatchedIntent, isNotNull);
      expect(controller.lastDispatchedIntent!['intent'], 'undo');
      expect(controller.lastDispatchedIntent!['target_index'], 0);
    });

    test('undo with no pending and last mover user pops only user move', () {
      runtime.bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': [
            ['X', null, null],
            [null, null, null],
            [null, null, null],
          ],
          'moves': [
            {'player': 'user', 'row': 0, 'col': 0, 'mark': 'X'},
          ],
          'turn': 'agent',
          'winner': null,
          'winning_line': null,
        },
      });
      controller.clickUndo();
      expect(controller.state.value.redoStack, hasLength(1));
      expect(controller.state.value.redoStack.first.user, const Cell(0, 0));
      expect(controller.state.value.redoStack.first.agent, isNull);
      expect(controller.lastDispatchedIntent!['target_index'], 0);
    });

    test('redo dispatches with TurnPair from stack', () {
      controller.applyTestSeed(
        const TicTacToeClientState(
          redoStack: [TurnPair(user: Cell(0, 0), agent: Cell(1, 0))],
        ),
      );
      controller.clickRedo();
      expect(controller.state.value.redoStack, isEmpty);
      expect(controller.lastDispatchedIntent!['intent'], 'redo');
    });

    test('redo disabled while pending non-null', () {
      controller.applyTestSeed(
        const TicTacToeClientState(
          pending: Cell(0, 0),
          redoStack: [TurnPair(user: Cell(0, 1))],
        ),
      );
      controller.clickRedo();
      // No dispatch.
      expect(controller.lastDispatchedIntent, isNull);
      // redoStack untouched.
      expect(controller.state.value.redoStack, hasLength(1));
    });
  });

  group('lifecycle helpers', () {
    test('newGame dispatches new_game intent', () async {
      final recording = _RecordingRuntime();
      recording.bus.setAgentState(const {});
      recording.sessionToReturn = FakeAgentSession();
      final c = TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
        runtime: recording,
      );
      addTearDown(c.dispose);
      c.newGame();
      await Future<void>.delayed(Duration.zero);
      expect(
        recording.lastStateOverlay!['_inbox']['tic_tac_toe']['intent'],
        'new_game',
      );
    });

    test('toggleAutoSend flips the flag', () {
      expect(controller.state.value.autoSend, isFalse);
      controller.toggleAutoSend();
      expect(controller.state.value.autoSend, isTrue);
      controller.toggleAutoSend();
      expect(controller.state.value.autoSend, isFalse);
    });

    test('setViewMode updates state', () {
      controller.setViewMode(TicTacToeViewMode.fullscreen);
      expect(controller.state.value.viewMode, TicTacToeViewMode.fullscreen);
    });

    test('auto-promote: hidden -> inline on first server game state', () {
      // Reset bus to empty BEFORE constructing a fresh controller so that
      // the controller starts with no game and viewMode == hidden.
      runtime.bus.setAgentState(const {});
      controller.dispose();
      controller = TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
        runtime: runtime,
      );
      expect(controller.state.value.viewMode, TicTacToeViewMode.hidden);
      runtime.bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': List.generate(3, (_) => List.filled(3, null)),
          'moves': <dynamic>[],
          'turn': 'user',
          'winner': null,
          'winning_line': null,
        },
      });
      expect(controller.state.value.viewMode, TicTacToeViewMode.inline);
    });

    test('auto-promote does not demote fullscreen', () {
      controller.setViewMode(TicTacToeViewMode.fullscreen);
      runtime.bus.setAgentState(const {});
      runtime.bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': List.generate(3, (_) => List.filled(3, null)),
          'moves': <dynamic>[],
          'turn': 'user',
          'winner': null,
          'winning_line': null,
        },
      });
      expect(controller.state.value.viewMode, TicTacToeViewMode.fullscreen);
    });
  });

  group('send', () {
    test('calls runtime.spawn with _inbox stateOverlay; sets inFlight true',
        () async {
      final recording = _RecordingRuntime();
      recording.bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': List.generate(3, (_) => List.filled(3, null)),
          'moves': <dynamic>[],
          'turn': 'user',
          'winner': null,
          'winning_line': null,
        },
      });
      final fakeSession = FakeAgentSession();
      recording.sessionToReturn = fakeSession;
      final c = TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
        runtime: recording,
      );
      addTearDown(c.dispose);
      c.clickCell(1, 1);
      expect(c.state.value.pending, isNotNull);
      c.send();
      // Synchronously: inFlight must already be true even though spawn is
      // async.
      expect(c.state.value.inFlight, isTrue);
      // Wait for the async spawn to register.
      await Future<void>.delayed(Duration.zero);
      expect(recording.lastRoomId, 'r');
      expect(recording.lastThreadId, 't');
      expect(recording.lastPrompt, 'Play (1, 1).');
      expect(
        recording.lastStateOverlay!['_inbox']['tic_tac_toe']['intent'],
        'play',
      );
    });

    test('clears redoStack on send', () {
      final recording = _RecordingRuntime();
      recording.bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': List.generate(3, (_) => List.filled(3, null)),
          'moves': <dynamic>[],
          'turn': 'user',
          'winner': null,
          'winning_line': null,
        },
      });
      recording.sessionToReturn = FakeAgentSession();
      final c = TicTacToeController(
        threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
        runtime: recording,
      );
      addTearDown(c.dispose);
      c.applyTestSeed(
        const TicTacToeClientState(
          pending: Cell(1, 1),
          redoStack: [TurnPair(user: Cell(0, 0), agent: Cell(1, 0))],
        ),
      );
      c.send();
      expect(c.state.value.redoStack, isEmpty);
    });
  });
}
