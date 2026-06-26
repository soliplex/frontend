import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../compute_display_messages.dart';
import '../execution_tracker.dart';
import '../tracker_registry.dart' show awaitingTrackerKey;
import '../run_id_resolver.dart';
import '../source_references_resolver.dart';
import '../unread_boundary.dart';
import 'message_tile.dart';
import 'scroll/anchored_scroll_controller.dart';
import 'scroll/scroll_to_bottom.dart';
import 'unread_divider.dart';
import 'workdir_files_section.dart';
import 'package:soliplex_design/soliplex_design.dart';

class MessageTimeline extends StatefulWidget {
  const MessageTimeline({
    super.key,
    required this.roomId,
    required this.messages,
    required this.messageStates,
    this.unreadBoundary = const BoundaryPending(),
    this.streamingState,
    this.executionTrackers = const {},
    this.onFeedbackSubmit,
    this.onInspect,
    this.onShowChunkVisualization,
    this.onFetchWorkdirFiles,
    this.onDownloadWorkdirFile,
    this.onPreviewWorkdirFile,
  });

  final String roomId;
  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;

  /// The read boundary for the open thread. The divider/scroll wait until it
  /// resolves so a not-yet-loaded null is not mistaken for "caught up".
  final UnreadBoundary unreadBoundary;
  final StreamingState? streamingState;
  final Map<String, ExecutionTracker> executionTrackers;
  final void Function(String runId, FeedbackType feedback, String? reason)?
      onFeedbackSubmit;
  final void Function(String runId)? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;
  final FetchWorkdirFiles? onFetchWorkdirFiles;
  final DownloadWorkdirFile? onDownloadWorkdirFile;
  final FetchWorkdirFileBytes? onPreviewWorkdirFile;

  @override
  State<MessageTimeline> createState() => _MessageTimelineState();
}

class _MessageTimelineState extends State<MessageTimeline> {
  late final AnchoredScrollController _scrollController;
  late final ScrollToBottomController _scrollToBottomController;

  final Map<String, GlobalKey> _messageKeys = {};
  String? _lastUserMessageId;
  bool _needsInitialScroll = true;

  /// The frozen first-unread message id, computed once when the boundary
  /// resolves. Drives both the divider and the one-time unread scroll. Stays
  /// fixed for the life of this timeline so live messages don't move it.
  String? _frozenFirstUnreadId;
  bool _unreadEvaluated = false;

  /// Gap left above a message when it is revealed at the top of the viewport.
  static const _revealTopGap = 8.0;

  /// Viewport height from the previous layout pass. Compared in
  /// [_maybeStickToBottomOnShrink] to detect the viewport shrinking when the
  /// on-screen keyboard opens: the Scaffold consumes the keyboard inset and
  /// hands the body a shorter constraint (the inset itself is stripped before
  /// it reaches here). Null until the first layout.
  double? _lastViewportHeight;

  /// Distance from the bottom within which the list counts as "resting at the
  /// bottom" for keyboard re-pinning. Mirrors the scroll-to-bottom button's
  /// near-bottom band so the two agree on what "at the bottom" means.
  static const _bottomStickThreshold = 100.0;

  Map<String, String?> _runIdMap = const {};
  Map<String, List<SourceReference>> _sourceReferencesMap = const {};

  @override
  void initState() {
    super.initState();
    _scrollController = AnchoredScrollController();
    _scrollToBottomController = ScrollToBottomController();
    _scrollController.addListener(_onScroll);
    _recomputeMaps();
  }

  @override
  void didUpdateWidget(MessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (widget.messages != oldWidget.messages ||
        widget.messageStates != oldWidget.messageStates) {
      _recomputeMaps();
    }

    final lastUserMsg = _findLastUserMessage(widget.messages);
    if (lastUserMsg != null && lastUserMsg.id != _lastUserMessageId) {
      _lastUserMessageId = lastUserMsg.id;
      _needsInitialScroll = false;
      _pinMessageAtTop(lastUserMsg.id);
    }

    final activeIds = widget.messages.map((m) => m.id).toSet();
    _messageKeys.removeWhere((id, _) => !activeIds.contains(id));

    _evaluateUnread(
      computeDisplayMessages(widget.messages, widget.streamingState),
    );
  }

  void _recomputeMaps() {
    _runIdMap = buildRunIdMap(widget.messages, widget.messageStates);
    _sourceReferencesMap =
        buildSourceReferencesMap(widget.messages, widget.messageStates);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _scrollToBottomController.dispose();
    super.dispose();
  }

  TextMessage? _findLastUserMessage(List<ChatMessage> messages) {
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      if (m is TextMessage && m.user == ChatUser.user) return m;
    }
    return null;
  }

  void _pinMessageAtTop(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      if (_tryPinAtTop(messageId)) return;

      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _tryPinAtTop(messageId);
      });
    });
  }

  /// Scroll offset that places [messageId]'s tile at the top of the viewport,
  /// or null if the tile is not laid out yet.
  double? _revealTopOffset(String messageId) {
    final key = _messageKeys[messageId];
    if (key?.currentContext == null) return null;
    final renderObject = key!.currentContext!.findRenderObject();
    if (renderObject == null) return null;
    final viewport = RenderAbstractViewport.of(renderObject);
    return viewport.getOffsetToReveal(renderObject, 0.0).offset - _revealTopGap;
  }

  bool _tryPinAtTop(String messageId) {
    final target = _revealTopOffset(messageId);
    if (target == null) return false;
    _scrollController.setAnchor(target);
    _scrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  /// Re-pins the list to the bottom when the viewport shrinks while the list
  /// is already resting at the bottom (within [_bottomStickThreshold]). The
  /// motivating case is the on-screen keyboard opening: the Scaffold reflows
  /// the body shorter, but the scroll offset would otherwise stay put and let
  /// the newest message slide below the fold. The trigger is the shrink
  /// itself, not the keyboard specifically — any Column sibling that claims
  /// space (e.g. the reconnect banner appearing) shrinks the viewport too, and
  /// re-pinning then is consistent with the near-bottom band the
  /// scroll-to-bottom button already uses. A user who has scrolled meaningfully
  /// up to read history (outside the band) is left in place. A no-op when the
  /// viewport grows or is unchanged — and therefore on desktop, where no
  /// keyboard ever shrinks it.
  void _maybeStickToBottomOnShrink(double viewportHeight) {
    final previous = _lastViewportHeight;
    _lastViewportHeight = viewportHeight;
    if (previous == null || viewportHeight >= previous) return;
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    // pos.pixels and pos.maxScrollExtent are from the previous frame —
    // not yet reconciled to the shrunk viewport.
    if (pos.maxScrollExtent - pos.pixels >= _bottomStickThreshold) return;
    _scrollToBottom();
  }

  void _scrollToUnread(String firstUnreadId, String? anchorId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_revealDividerAtTop(firstUnreadId)) {
        _nudgeToShowAnchor(firstUnreadId, anchorId);
        return;
      }
      // Divider off-screen: jump to the bottom to lay out the (recent) reply,
      // then retry.
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        if (_revealDividerAtTop(firstUnreadId)) {
          _nudgeToShowAnchor(firstUnreadId, anchorId);
        }
      });
    });
  }

  /// Freezes the unread boundary and performs the one-time unread scroll the
  /// first time the boundary is resolved. Idempotent: once evaluated it never
  /// re-fires, so live-arriving messages neither move the divider nor yank the
  /// viewport.
  void _evaluateUnread(List<ChatMessage> displayMessages) {
    if (_unreadEvaluated) return;
    final boundary = widget.unreadBoundary;
    if (boundary is! BoundaryResolved) return;
    _unreadEvaluated = true;
    _frozenFirstUnreadId =
        firstUnreadMessageId(displayMessages, boundary.anchorId);
    if (widget.streamingState == null && _frozenFirstUnreadId != null) {
      _scrollToUnread(_frozenFirstUnreadId!, boundary.anchorId);
    }
  }

  /// Jumps so the divider sits at the top of the viewport. Returns false if the
  /// divider tile isn't laid out yet (caller retries after a layout pass).
  ///
  /// Revealing the divider at the top is also what makes the *preceding* anchor
  /// message measurable: it then sits within the leading cache extent, so
  /// [_nudgeToShowAnchor] (next frame) can read its offset. Measuring the anchor
  /// from the bottom, where it is off-screen above a tall reply, returns null.
  bool _revealDividerAtTop(String firstUnreadId) {
    final dividerTop = _revealTopOffset(firstUnreadId);
    if (dividerTop == null) return false;
    _scrollController.jumpTo(
        dividerTop.clamp(0.0, _scrollController.position.maxScrollExtent));
    return true;
  }

  /// With the divider at the top, the preceding anchor message is laid out, so
  /// nudge up to show it above the divider — bounded to a third of the viewport
  /// so the divider stays visible even for a tall anchor (see
  /// [unreadScrollOffset]). Keeps the divider at the top if the anchor still
  /// can't be measured.
  void _nudgeToShowAnchor(String firstUnreadId, String? anchorId) {
    if (anchorId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final dividerTop = _revealTopOffset(firstUnreadId);
      final anchorTop = _revealTopOffset(anchorId);
      if (dividerTop == null || anchorTop == null) return;
      final target = unreadScrollOffset(
        anchorTop: anchorTop,
        dividerTop: dividerTop,
        contextBudget: _scrollController.position.viewportDimension / 3,
      );
      _scrollController.jumpTo(
          target.clamp(0.0, _scrollController.position.maxScrollExtent));
    });
  }

  void _onScroll() {
    _scrollToBottomController.updateScrollPosition(_scrollController);
  }

  void _onScrollToBottom() {
    _scrollController.clearAnchor();
    _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
    _scrollToBottomController.hide();
  }

  GlobalKey _keyFor(String id) {
    return _messageKeys.putIfAbsent(id, () => GlobalKey());
  }

  @override
  Widget build(BuildContext context) {
    final displayMessages = computeDisplayMessages(
      widget.messages,
      widget.streamingState,
    );

    _evaluateUnread(displayMessages);

    if (_needsInitialScroll) {
      _lastUserMessageId = _findLastUserMessage(widget.messages)?.id;
      // Defer the one-time initial scroll until we know where to land: follow a
      // streaming run to the bottom right away, otherwise wait for the unread
      // boundary to resolve so a caught-up thread lands at the bottom and an
      // unread one is taken to its divider by _evaluateUnread. Acting before the
      // boundary resolves would land at the bottom and then jump once the disk
      // load resolves after the first build.
      if (widget.streamingState != null) {
        _needsInitialScroll = false;
        _scrollToBottom();
      } else if (widget.unreadBoundary is BoundaryResolved) {
        _needsInitialScroll = false;
        if (_frozenFirstUnreadId == null) _scrollToBottom();
      }
    }

    final streamingPhase = widget.streamingState != null
        ? switch (widget.streamingState!) {
            AwaitingText(:final currentPhase) => currentPhase,
            TextStreaming(:final currentPhase) => currentPhase,
          }
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        // The viewport height drops when the keyboard opens (the Scaffold
        // reflows the body shorter); keep the latest message pinned above the
        // input bar when it does.
        _maybeStickToBottomOnShrink(constraints.maxHeight);
        return Stack(
          children: [
            CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.all(SoliplexSpacing.s4),
                  sliver: SliverList.builder(
                    itemCount: displayMessages.length,
                    itemBuilder: (context, index) {
                      final message = displayMessages[index];
                      final isLastItem = index == displayMessages.length - 1;
                      // A distinct key for the loading sentinel forces a
                      // remount at the AwaitingText → TextStreaming transition.
                      // Children capture their MessageExpansion handle once in
                      // initState; without the remount they would stay bound to
                      // loadingMessageId (which forMessage rejects) and never
                      // acquire a handle under the real messageId.
                      final tile = MessageTile(
                        roomId: widget.roomId,
                        message: message,
                        runId: _runIdMap[message.id] ??
                            (message is TextMessage &&
                                    message.user == ChatUser.user
                                ? widget.messageStates[message.id]?.runId
                                : null),
                        sourceReferences: _sourceReferencesMap[message.id],
                        onFeedbackSubmit: widget.onFeedbackSubmit,
                        onInspect: widget.onInspect,
                        onShowChunkVisualization:
                            widget.onShowChunkVisualization,
                        onFetchWorkdirFiles: widget.onFetchWorkdirFiles,
                        onDownloadWorkdirFile: widget.onDownloadWorkdirFile,
                        onPreviewWorkdirFile: widget.onPreviewWorkdirFile,
                        executionTracker: widget
                                .executionTrackers[message.id] ??
                            (message is LoadingMessage
                                ? widget.executionTrackers[awaitingTrackerKey]
                                : null),
                        streamingPhase: isLastItem ? streamingPhase : null,
                      );
                      return Padding(
                        key: message is LoadingMessage
                            ? const ValueKey('loading')
                            : _keyFor(message.id),
                        padding:
                            const EdgeInsets.only(bottom: SoliplexSpacing.s4),
                        child: message.id == _frozenFirstUnreadId
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [const UnreadDivider(), tile],
                              )
                            : tile,
                      );
                    },
                  ),
                ),
              ],
            ),
            Positioned(
              right: SoliplexSpacing.s4,
              bottom: SoliplexSpacing.s4,
              child: ScrollToBottomButton(
                controller: _scrollToBottomController,
                onPressed: _onScrollToBottom,
              ),
            ),
          ],
        );
      },
    );
  }
}
