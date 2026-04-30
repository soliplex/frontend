import 'package:flutter/foundation.dart' show immutable, listEquals;

/// One cell on the 3x3 board.
@immutable
class Cell {
  const Cell(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Cell && row == other.row && col == other.col;

  @override
  int get hashCode => Object.hash(row, col);

  @override
  String toString() => 'Cell($row, $col)';
}

/// One full turn — the user's move and the agent's response (if any).
/// The agent's move is null when the user's move ended the game.
@immutable
class TurnPair {
  const TurnPair({required this.user, this.agent});

  final Cell user;
  final Cell? agent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TurnPair && user == other.user && agent == other.agent;

  @override
  int get hashCode => Object.hash(user, agent);
}

enum TicTacToeViewMode { hidden, inline, fullscreen }

enum TicTacToeError { network, toolRejected }

/// Client-only state held by [TicTacToeController].
@immutable
class TicTacToeClientState {
  const TicTacToeClientState({
    this.pending,
    this.redoStack = const [],
    this.viewMode = TicTacToeViewMode.hidden,
    this.autoSend = false,
    this.inFlight = false,
    this.lastError,
    this.unreadChatWhileFullscreen = 0,
    this.bannerVisible = false,
  });

  final Cell? pending;
  final List<TurnPair> redoStack;
  final TicTacToeViewMode viewMode;
  final bool autoSend;
  final bool inFlight;
  final TicTacToeError? lastError;
  final int unreadChatWhileFullscreen;
  final bool bannerVisible;

  /// Copy with optional overrides. Use [clearPending] / [clearLastError]
  /// to force the corresponding field to null (since named parameters
  /// can't disambiguate "leave alone" vs "set null" otherwise).
  TicTacToeClientState copyWith({
    Cell? pending,
    bool clearPending = false,
    List<TurnPair>? redoStack,
    TicTacToeViewMode? viewMode,
    bool? autoSend,
    bool? inFlight,
    TicTacToeError? lastError,
    bool clearLastError = false,
    int? unreadChatWhileFullscreen,
    bool? bannerVisible,
  }) {
    return TicTacToeClientState(
      pending: clearPending ? null : (pending ?? this.pending),
      redoStack: redoStack ?? this.redoStack,
      viewMode: viewMode ?? this.viewMode,
      autoSend: autoSend ?? this.autoSend,
      inFlight: inFlight ?? this.inFlight,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      unreadChatWhileFullscreen:
          unreadChatWhileFullscreen ?? this.unreadChatWhileFullscreen,
      bannerVisible: bannerVisible ?? this.bannerVisible,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TicTacToeClientState &&
          pending == other.pending &&
          listEquals(redoStack, other.redoStack) &&
          viewMode == other.viewMode &&
          autoSend == other.autoSend &&
          inFlight == other.inFlight &&
          lastError == other.lastError &&
          unreadChatWhileFullscreen == other.unreadChatWhileFullscreen &&
          bannerVisible == other.bannerVisible;

  @override
  int get hashCode => Object.hash(
        pending,
        Object.hashAll(redoStack),
        viewMode,
        autoSend,
        inFlight,
        lastError,
        unreadChatWhileFullscreen,
        bannerVisible,
      );
}
