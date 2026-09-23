import 'package:soliplex_agent/soliplex_agent.dart';

import 'execution_tracker.dart';

/// Sentinel id for the placeholder [LoadingMessage] shown while a run has yet
/// to say anything. It is reused across runs, so it must never be used as a
/// persistence key — state written under it would leak into the next reply.
const loadingMessageId = '_loading';

/// What the timeline shows: a tile and the execution band it renders.
typedef RenderedTile = ({
  ChatMessage message,
  ExecutionTracker? band,
});

/// A band [layOutTimeline] found no place for, and so left out: its key, the
/// run it names if one is known, how many entries it held, and the tile it
/// would have been the second band on, or null when it had no tile at all.
typedef DroppedBand = ({
  String band,
  String? runId,
  int entries,
  String? tile,
});

/// The tiles the timeline shows, and the bands left out of them.
typedef TimelineLayout = ({
  List<RenderedTile> tiles,
  List<DroppedBand> dropped,
});

/// The tiles the timeline shows, and the band each one renders.
///
/// One decision in one place, so that the property every caller depends on is
/// checkable rather than spread across the code that happens to produce the
/// inputs:
///
/// > every terminal run with a parked outcome has a band-capable assistant
/// > tile, and every band attaches exactly once to a band-capable tile of the
/// > run that produced it.
///
/// Total, and identical on the live and reload paths because it reads only what
/// both of them produce: the committed [messages], the accumulated [bands], the
/// [outcomes] parked per run, and the [streaming] state of the run named by
/// [activeRunId].
///
/// Four steps, in order.
///
/// 1. **Project** — merge [streaming] into the message list, so a reply is
///    visible between `TEXT_MESSAGE_START` and `TEXT_MESSAGE_END` rather than
///    only once it commits.
/// 2. **Filter** — leave out a message opened only to give a tool call's
///    `parentMessageId` a target ([existsOnlyForToolCall]).
/// 3. **Guarantee** — give a run left with no band-capable tile, or with work no
///    message spoke for, its parked outcome, so the work the user watched still
///    has somewhere to render.
/// 4. **Place** — hand each band to a band-capable tile of its own run: a
///    claimed band to the message that claimed it, an unclaimed one to the
///    run's last. A band with no such tile comes back in `dropped`, for the
///    caller to report.
TimelineLayout layOutTimeline({
  required List<ChatMessage> messages,
  required Map<String, ExecutionTracker> bands,
  required Map<String, NoResponseTile> outcomes,
  required StreamingState? streaming,
  required String? activeRunId,
}) {
  final projected = _project(messages, streaming, activeRunId);
  final shown = _guaranteeATilePerRun(
    projected: projected,
    outcomes: outcomes,
    activeRunId: activeRunId,
    // A run can reach its end with work no message ever spoke for: a closing
    // response that reasons and calls a tool and says nothing. Its band is
    // still keyed by the run, and a run that already has a reply would
    // otherwise be judged represented and the band left with nowhere to go.
    withUnclaimedWork: {
      for (final runId in outcomes.keys)
        if (bands[noResponseMessageId(runId)]?.hasWork ?? false) runId,
    },
  );
  return _placeBands(
    tiles: shown,
    bands: bands,
    knownRuns: {
      for (final tile in shown)
        if (tile.runId case final runId?) runId,
      ...outcomes.keys,
    },
  );
}

/// [tiles] with each band handed to a band-capable assistant tile of its own
/// run.
///
/// A band keyed to a message goes to the first band-capable tile of its run at
/// or after that message. An **unclaimed** band is keyed [noResponseMessageId]
/// of its run rather than a message id: it is the run's latest response, the
/// one still open or the one that ended without a message speaking for it, so
/// it goes to the run's last band-capable tile — the loading or streaming tile
/// while the run is live, and its outcome tile once it has ended.
///
/// A band that resolves to neither is left out and returned as dropped. A drop
/// detects a broken invariant rather than enforcing it, and is a defect rather
/// than noise: a band rendering nowhere means the run's work vanished from a
/// turn the user watched happen.
TimelineLayout _placeBands({
  required List<ChatMessage> tiles,
  required Map<String, ExecutionTracker> bands,
  required Set<String> knownRuns,
}) {
  final placed = List<ExecutionTracker?>.filled(tiles.length, null);
  final dropped = <DroppedBand>[];
  final runOfUnclaimedBand = {
    for (final runId in knownRuns) noResponseMessageId(runId): runId,
  };

  for (final MapEntry(key: key, value: band) in bands.entries) {
    // A message id first. A run's outcome tile carries the id its unclaimed
    // band is keyed by, and is the run's last band-capable tile, so both
    // readings of that key reach the same tile.
    final named = tiles.indexWhere((t) => t.id == key);
    final (runId, target) = named >= 0
        ? (
            tiles[named].runId,
            _firstBandCapableAt(tiles, from: named, inRun: tiles[named].runId),
          )
        : switch (runOfUnclaimedBand[key]) {
            final String runId => (runId, _lastBandCapableIn(tiles, runId)),
            null => (null, -1),
          };
    if (target < 0 || placed[target] != null) {
      dropped.add((
        band: key,
        runId: runId,
        entries: band.timeline.value.length,
        tile: target < 0 ? null : tiles[target].id,
      ));
      continue;
    }
    placed[target] = band;
  }

  return (
    tiles: [
      for (var i = 0; i < tiles.length; i++)
        (message: tiles[i], band: placed[i]),
    ],
    dropped: dropped,
  );
}

/// The index of the first tile of [inRun] at or after [from] that can host a
/// band, or `-1` when the run has none. User tiles and diagnostic rows are
/// skipped: they render no band, so stopping on one would lose it.
int _firstBandCapableAt(
  List<ChatMessage> tiles, {
  required int from,
  required String? inRun,
}) {
  for (var i = from; i < tiles.length; i++) {
    final tile = tiles[i];
    if (tile.runId == inRun && _standsInForItsRun(tile)) return i;
  }
  return -1;
}

/// The index of the last tile of [runId] that can host a band, or `-1` when
/// the run has none.
int _lastBandCapableIn(
  List<ChatMessage> tiles,
  String runId,
) {
  for (var i = tiles.length - 1; i >= 0; i--) {
    final tile = tiles[i];
    if (tile.runId == runId && _standsInForItsRun(tile)) return i;
  }
  return -1;
}

/// One tile per message that survives the filter, plus the parked outcome of
/// every run that ended with no band-capable tile or with work no message
/// spoke for, and an error row for a failed run that shows no outcome tile.
///
/// A run's outcome takes the place its messages held, so a run that went quiet
/// before an unrelated question renders above that question rather than after
/// it. A message that names no run closes the run before it, which is what puts
/// that outcome ahead of a turn still waiting for its own run to begin.
List<ChatMessage> _guaranteeATilePerRun({
  required List<ChatMessage> projected,
  required Map<String, NoResponseTile> outcomes,
  required String? activeRunId,
  required Set<String> withUnclaimedWork,
}) {
  final shown = [
    for (final message in projected)
      if (!existsOnlyForToolCall(message)) message,
  ];
  final representedRuns = {
    for (final message in shown)
      if (message.runId case final runId?)
        if (_standsInForItsRun(message)) runId,
  };
  final owed = {
    for (final runId in outcomes.keys)
      if (runId != activeRunId &&
          (!representedRuns.contains(runId) ||
              withUnclaimedWork.contains(runId)))
        runId,
  };
  // A run already showing how it ended needs nothing added; one that ended in
  // failure and is represented by something else does.
  final runsReportingThemselves = {
    for (final message in shown)
      if (message is NoResponseTile) message.runId,
  };
  // A failed run whose reply survives keeps that reply, so its outcome tile is
  // suppressed — and with it the only account of why the run failed. The
  // failure is reported beside the reply instead, unless the run is owed its
  // outcome tile anyway, which already says the run failed.
  final unreported = {
    for (final MapEntry(key: runId, value: outcome) in outcomes.entries)
      if (runId != activeRunId &&
          representedRuns.contains(runId) &&
          !owed.contains(runId) &&
          !runsReportingThemselves.contains(runId) &&
          outcome.reason == TerminalReason.failed)
        runId,
  };

  // `outcomes` is parked in the order runs ended. A tile carries its own time
  // too, but only when the terminal that parked it had one, so the order is
  // what places a run that committed nothing.
  final endedIn = outcomes.keys.toList();

  final tiles = <ChatMessage>[];
  void settle(String runId) {
    if (owed.remove(runId)) {
      tiles.add(outcomes[runId]!);
      return;
    }
    if (!unreported.remove(runId)) return;
    tiles.add(
      ErrorMessage.create(
        id: runErrorMessageId(runId),
        message: outcomes[runId]!.errorDetail ?? '',
        createdAt: outcomes[runId]!.createdAt,
        runId: runId,
      ),
    );
  }

  /// Settles every owed run that ended before [runId] did, when that is
  /// known, and nothing at all when it is not.
  ///
  /// A run that committed nothing has no message to sit beside, so without
  /// this its outcome falls to the sweep below and lands at the foot of the
  /// timeline — under a later run's answer, carrying its band with it.
  ///
  /// Every run that ends records how it ended, so a run missing from that
  /// record has not ended: it is the one still in flight, and everything owed
  /// ended before it. A run that is missing for any other reason says nothing
  /// about when it ended, and reading it as the latest would hoist a later
  /// run's outcome above a turn that came first — so that case settles
  /// nothing here and leaves the sweep to place what is owed.
  void settleRunsEndingBefore(String runId) {
    final limit = endedIn.indexOf(runId);
    if (limit < 0) {
      if (runId != activeRunId) return;
      endedIn.forEach(settle);
      return;
    }
    endedIn.take(limit).forEach(settle);
  }

  String? openRun;
  for (final message in projected) {
    final runId = message.runId;
    if (openRun != null && runId != openRun) settle(openRun);
    if (runId != null) settleRunsEndingBefore(runId);
    openRun = runId;
    if (existsOnlyForToolCall(message)) continue;
    tiles.add(message);
  }
  // Whatever is still owed ended after everything the timeline holds, so it
  // belongs at the foot of it, in the order the runs ended.
  for (final runId in endedIn) {
    settle(runId);
  }
  return tiles;
}

/// Whether [message] is a tile that can host a run's execution band, and so
/// stands in for the run rather than needing its outcome beside it.
///
/// A user message and the diagnostic rows host no band. Suppressing a run's
/// outcome on one of those would leave the run's work with nowhere to render,
/// which is the whole failure this function exists to make impossible.
///
/// [GenUiMessage] sits on the non-standing side, so a run that produced only
/// one would show a GenUi tile beside a "no response" tile. That combination is
/// unsupported rather than intended: the AG-UI processor has no minting site
/// for [GenUiMessage], so a GenUi-only run cannot occur. Supporting one needs a
/// band-capable renderer and a revised rule here, together.
///
/// Written as an exhaustive switch so the next [ChatMessage] variant is a
/// compile error rather than a silent `false`.
bool _standsInForItsRun(ChatMessage message) => switch (message) {
      TextMessage(:final user) => user == ChatUser.assistant,
      NoResponseTile() => true,
      LoadingMessage() => true,
      ToolCallMessage() => false,
      ErrorMessage() => false,
      GenUiMessage() => false,
      DroppedEventMessage() => false,
    };

/// [messages] with [streaming] merged in.
///
/// A reply is not committed to `Conversation.messages` until
/// `TEXT_MESSAGE_END`, so without this an ordinary answer is invisible for as
/// long as it streams.
///
/// A reply that has yet to say anything renders as the loading sentinel rather
/// than as an empty bubble. That is the window between `TEXT_MESSAGE_START` and
/// the first delta — the window a message opened only to name a tool call never
/// leaves — and no claim has arrived yet to tell the two apart. Which it turns
/// out to be is settled when it commits.
List<ChatMessage> _project(
  List<ChatMessage> messages,
  StreamingState? streaming,
  String? activeRunId,
) {
  if (streaming == null) return messages;
  return switch (streaming) {
    AwaitingText() => [
        ...messages,
        LoadingMessage.create(id: loadingMessageId, runId: activeRunId),
      ],
    TextStreaming(:final messageId, :final text) when text.trim().isEmpty => [
        ...messages.where((m) => m.id != messageId),
        LoadingMessage.create(id: loadingMessageId, runId: activeRunId),
      ],
    TextStreaming(
      :final messageId,
      :final user,
      :final text,
      :final thinkingText,
    ) =>
      [
        ...messages.where((m) => m.id != messageId),
        TextMessage(
          id: messageId,
          user: user,
          // No server time exists mid-stream; the caption fills when the
          // message commits with the backend's event time on TextMessageEnd,
          // rather than flashing a client clock.
          createdAt: null,
          text: text,
          thinkingText: thinkingText,
          runId: activeRunId,
        ),
      ],
  };
}
