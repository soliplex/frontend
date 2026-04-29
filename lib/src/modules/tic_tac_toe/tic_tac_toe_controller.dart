import 'dart:async';

import 'package:meta/meta.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide computed;

import 'board_render_state.dart';
import 'tic_tac_toe_intent.dart';
import 'tic_tac_toe_projection.dart';
import 'tic_tac_toe_server_state.dart';
import 'tic_tac_toe_state.dart';

/// Per-thread tic-tac-toe controller. Held by [TicTacToeRegistry];
/// constructed lazily by widgets through [TicTacToeRegistry.controllerFor].
class TicTacToeController {
  TicTacToeController({
    required this.threadKey,
    required AgentRuntime runtime,
  }) : _runtime = runtime {
    final bus = runtime.ensureThreadState(threadKey).bus;
    _serverSignal = bus.project(const TicTacToeProjection());
    _state = signal(const TicTacToeClientState());
    _boardRender = computed(
      () => BoardRenderState.compose(
        server: _serverSignal.value,
        client: _state.value,
      ),
    );
    _serverSubscription = _serverSignal.subscribe(_onServerState);
  }

  final ThreadKey threadKey;
  final AgentRuntime _runtime;

  late final ReadonlySignal<TicTacToeServerState?> _serverSignal;
  late final Signal<TicTacToeClientState> _state;
  late final ReadonlySignal<BoardRenderState?> _boardRender;
  void Function()? _serverSubscription;
  AgentSession? _activeSession;
  bool _disposed = false;

  /// Visible to tests so we can assert dispatched intents without
  /// actually spawning runs against a fake runtime.
  @visibleForTesting
  Map<String, dynamic>? lastDispatchedIntent;

  ReadonlySignal<TicTacToeClientState> get state => _state.readonly();
  ReadonlySignal<BoardRenderState?> get boardRender => _boardRender;

  /// Stage / replace / toggle a pending move.
  void clickCell(int row, int col) {
    final s = _state.value;
    if (s.inFlight) return;
    final server = _serverSignal.value;
    if (server == null) return;
    if (server.winner != null) return;
    if (server.board[row][col] != null) return;

    final cell = Cell(row, col);
    if (s.pending == cell) {
      _state.value = s.copyWith(clearPending: true);
      return;
    }
    _state.value = s.copyWith(pending: cell);

    if (s.autoSend && _state.value.pending != null) {
      send();
    }
  }

  /// Undo: clears pending, OR sends an undo intent for committed history.
  void clickUndo() {
    final s = _state.value;
    if (s.inFlight) return;
    if (s.pending != null) {
      _state.value = s.copyWith(clearPending: true);
      return;
    }
    final server = _serverSignal.value;
    if (server == null) return;
    final moves = server.moves;
    if (moves.isEmpty) return;

    final lastIsAgent = moves.last.player == TicTacToePlayer.agent;
    final pairCount = lastIsAgent ? 2 : 1;
    final targetIndex = moves.length - pairCount;

    final undoneUser = moves[moves.length - pairCount];
    final undoneAgent = lastIsAgent ? moves.last : null;
    final newRedoStack = [
      ...s.redoStack,
      TurnPair(
        user: Cell(undoneUser.row, undoneUser.col),
        agent:
            undoneAgent == null ? null : Cell(undoneAgent.row, undoneAgent.col),
      ),
    ];
    _state.value = s.copyWith(redoStack: newRedoStack);

    _dispatch({
      TicTacToeIntent.intentKey: TicTacToeIntent.undo,
      'target_index': targetIndex,
    });
  }

  void clickRedo() {
    final s = _state.value;
    if (s.inFlight) return;
    if (s.pending != null) return;
    if (s.redoStack.isEmpty) return;
    final pair = s.redoStack.last;
    final newStack = s.redoStack.sublist(0, s.redoStack.length - 1);
    _state.value = s.copyWith(redoStack: newStack);

    final movesPayload = <Map<String, dynamic>>[
      {
        'player': 'user',
        'row': pair.user.row,
        'col': pair.user.col,
        'mark': 'X',
      },
      if (pair.agent != null)
        {
          'player': 'agent',
          'row': pair.agent!.row,
          'col': pair.agent!.col,
          'mark': 'O',
        },
    ];
    _dispatch({
      TicTacToeIntent.intentKey: TicTacToeIntent.redo,
      'moves': movesPayload,
    });
  }

  /// Test-only seed for the client state.
  @visibleForTesting
  void applyTestSeed(TicTacToeClientState seed) {
    _state.value = seed;
  }

  void send() {
    final s = _state.value;
    final server = _serverSignal.value;
    if (s.inFlight) return;
    if (s.pending == null) return;
    if (server == null) return;
    if (server.winner != null) return;
    if (server.turn != TicTacToePlayer.user) return;

    final overlay = <String, dynamic>{
      '_inbox': {
        TicTacToeIntent.surfaceKey: {
          TicTacToeIntent.intentKey: TicTacToeIntent.play,
          'move': {'row': s.pending!.row, 'col': s.pending!.col},
        },
      },
    };

    _state.value = s.copyWith(
      inFlight: true,
      redoStack: const [],
      clearLastError: true,
    );
    unawaited(_runWithOverlay(overlay));
  }

  Future<void> _runWithOverlay(Map<String, dynamic> overlay) async {
    final (:roomId, :threadId, serverId: _) = threadKey;
    try {
      _activeSession = await _runtime.spawn(
        roomId: roomId,
        prompt: '',
        threadId: threadId,
        stateOverlay: overlay,
      );
      await _activeSession!.awaitResult();
    } on Object {
      if (!_disposed) {
        _state.value = _state.value.copyWith(
          lastError: TicTacToeError.network,
        );
      }
    } finally {
      _activeSession = null;
      if (!_disposed) {
        _state.value = _state.value.copyWith(inFlight: false);
      }
    }
  }

  void cancel() {
    _activeSession?.cancel();
    _state.value = _state.value.copyWith(clearPending: true);
  }

  /// Dispatch a `new_game` intent to the agent.
  void newGame() {
    final overlay = <String, dynamic>{
      '_inbox': {
        TicTacToeIntent.surfaceKey: {
          TicTacToeIntent.intentKey: TicTacToeIntent.newGame,
        },
      },
    };
    _state.value = _state.value.copyWith(
      inFlight: true,
      redoStack: const [],
      clearPending: true,
      clearLastError: true,
    );
    unawaited(_runWithOverlay(overlay));
  }

  void toggleAutoSend() {
    _state.value = _state.value.copyWith(autoSend: !_state.value.autoSend);
  }

  void setViewMode(TicTacToeViewMode mode) {
    _state.value = _state.value.copyWith(viewMode: mode);
  }

  void _onServerState(TicTacToeServerState? server) {
    if (_disposed) return;
    final s = _state.value;
    if (server != null && s.viewMode == TicTacToeViewMode.hidden) {
      _state.value = s.copyWith(viewMode: TicTacToeViewMode.inline);
    }
    if (server != null && s.pending != null) {
      final p = s.pending!;
      if (server.board[p.row][p.col] != null) {
        _state.value = _state.value.copyWith(clearPending: true);
      }
    }
  }

  void _dispatch(Map<String, dynamic> intent) {
    lastDispatchedIntent = intent;
    final overlay = <String, dynamic>{
      '_inbox': {TicTacToeIntent.surfaceKey: intent},
    };
    _state.value = _state.value.copyWith(
      inFlight: true,
      clearLastError: true,
    );
    unawaited(_runWithOverlay(overlay));
  }

  void dispose() {
    _disposed = true;
    _activeSession?.cancel();
    _serverSubscription?.call();
    _state.dispose();
  }
}
