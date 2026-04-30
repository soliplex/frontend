import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/room_providers.dart';
import 'package:soliplex_frontend/src/modules/room/run_registry.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/tic_tac_toe_module.dart';
import 'package:soliplex_frontend/src/modules/tic_tac_toe/ui/tic_tac_toe_board.dart';

class _FakeRuntime implements AgentRuntime {
  _FakeRuntime() : threadState = ThreadState();

  final ThreadState threadState;
  StateBus get bus => threadState.bus;

  Map<String, dynamic>? lastOverlay;
  String? lastRoomId;
  String? lastThreadId;
  String? lastPrompt;

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
    lastOverlay = stateOverlay;

    final inbox = (stateOverlay!['_inbox']
        as Map<String, dynamic>)['tic_tac_toe'] as Map<String, dynamic>;
    if (inbox['intent'] == 'play') {
      final move = inbox['move'] as Map<String, dynamic>;
      final ur = move['row'] as int;
      final uc = move['col'] as int;
      bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': [
            for (int r = 0; r < 3; r++)
              [
                for (int c = 0; c < 3; c++)
                  if (r == ur && c == uc)
                    'X'
                  else if (r == 2 && c == 2)
                    'O'
                  else
                    null,
              ],
          ],
          'moves': [
            {'player': 'user', 'row': ur, 'col': uc, 'mark': 'X'},
            {'player': 'agent', 'row': 2, 'col': 2, 'mark': 'O'},
          ],
          'turn': 'user',
          'winner': null,
          'winning_line': null,
        },
      });
    }
    return _StubSession();
  }

  @override
  dynamic noSuchMethod(Invocation i) {
    if (i.memberName == #ensureThreadState) return threadState;
    return super.noSuchMethod(i);
  }
}

class _StubSession implements AgentSession {
  @override
  Future<AgentResult> awaitResult({Duration? timeout}) async =>
      const AgentSuccess(
        runId: 'fake-run',
        threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
        output: '',
      );

  @override
  void cancel() {}

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  testWidgets(
    'binding round-trip: tap, server delta, board renders both moves',
    (tester) async {
      final runtime = _FakeRuntime();
      runtime.bus.setAgentState({
        'game': {
          'id': 'g1',
          'board': [
            [null, null, null],
            [null, null, null],
            [null, null, null],
          ],
          'moves': <dynamic>[],
          'turn': 'user',
          'winner': null,
          'winning_line': null,
        },
      });

      final mod = TicTacToeAppModule();
      final routes = mod.build();
      addTearDown(mod.onDispose);

      final runRegistry = RunRegistry();
      addTearDown(runRegistry.dispose);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...routes.overrides,
            runRegistryProvider.overrideWithValue(runRegistry),
            roomActiveThreadProvider.overrideWithValue(
              (
                threadKey: (serverId: 's', roomId: 'r', threadId: 't'),
                runtime: runtime,
              ),
            ),
          ],
          child: const MaterialApp(
            home: Scaffold(body: TicTacToeBoard()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('cell-1-1')));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
      await tester.pumpAndSettle();

      expect(find.text('X'), findsOneWidget);
      expect(find.text('O'), findsOneWidget);
      expect(runtime.lastOverlay, isNotNull);
      expect(runtime.lastRoomId, 'r');
      expect(runtime.lastThreadId, 't');
      expect(runtime.lastPrompt, 'Play (1, 1).');
    },
  );
}
