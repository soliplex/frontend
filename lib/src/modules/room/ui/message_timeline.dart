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
    this.unreadBoundaryId,
    this.unreadBoundaryResolved = false,
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
  final String? unreadBoundaryId;

  /// Whether [unreadBoundaryId] reflects a resolved read state (vs. the anchor
  /// not having loaded yet). The divider/scroll wait for this so a not-yet-
  /// loaded null is not mistaken for "caught up".
  final bool unreadBoundaryResolved;
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

  bool _tryPinAtTop(String messageId) {
    final key = _messageKeys[messageId];
    if (key?.currentContext == null) return false;

    final renderObject = key!.currentContext!.findRenderObject();
    if (renderObject == null) return false;
    final viewport = RenderAbstractViewport.of(renderObject);
    final target = viewport.getOffsetToReveal(renderObject, 0.0).offset - 8;

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

  void _scrollToUnread(String messageId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (_tryRevealAtTop(messageId)) return;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollController.hasClients) return;
        _tryRevealAtTop(messageId);
      });
    });
  }

  /// Freezes the unread boundary and performs the one-time unread scroll the
  /// first time the boundary is resolved. Idempotent: once evaluated it never
  /// re-fires, so live-arriving messages neither move the divider nor yank the
  /// viewport.
  void _evaluateUnread(List<ChatMessage> displayMessages) {
    if (_unreadEvaluated || !widget.unreadBoundaryResolved) return;
    _unreadEvaluated = true;
    _frozenFirstUnreadId =
        firstUnreadMessageId(displayMessages, widget.unreadBoundaryId);
    if (widget.streamingState == null && _frozenFirstUnreadId != null) {
      _scrollToUnread(_frozenFirstUnreadId!);
    }
  }

  bool _tryRevealAtTop(String messageId) {
    final key = _messageKeys[messageId];
    if (key?.currentContext == null) return false;

    final renderObject = key!.currentContext!.findRenderObject();
    if (renderObject == null) return false;
    final viewport = RenderAbstractViewport.of(renderObject);
    final target = (viewport.getOffsetToReveal(renderObject, 0.0).offset - 8)
        .clamp(0.0, _scrollController.position.maxScrollExtent);
    _scrollController.jumpTo(target);
    return true;
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
      _needsInitialScroll = false;
      _lastUserMessageId = _findLastUserMessage(widget.messages)?.id;
      // _evaluateUnread scrolls to the divider only when one is resolved AND no
      // run is streaming; otherwise (caught up, not yet resolved, or an active
      // run we should follow) land at the bottom.
      if (_frozenFirstUnreadId == null || widget.streamingState != null) {
        _scrollToBottom();
      }
    }

    final streamingPhase = widget.streamingState != null
        ? switch (widget.streamingState!) {
            AwaitingText(:final currentPhase) => currentPhase,
            TextStreaming(:final currentPhase) => currentPhase,
          }
        : null;

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
                        (message is TextMessage && message.user == ChatUser.user
                            ? widget.messageStates[message.id]?.runId
                            : null),
                    sourceReferences: _sourceReferencesMap[message.id],
                    onFeedbackSubmit: widget.onFeedbackSubmit,
                    onInspect: widget.onInspect,
                    onShowChunkVisualization: widget.onShowChunkVisualization,
                    onFetchWorkdirFiles: widget.onFetchWorkdirFiles,
                    onDownloadWorkdirFile: widget.onDownloadWorkdirFile,
                    onPreviewWorkdirFile: widget.onPreviewWorkdirFile,
                    executionTracker: widget.executionTrackers[message.id] ??
                        (message is LoadingMessage
                            ? widget.executionTrackers[awaitingTrackerKey]
                            : null),
                    streamingPhase: isLastItem ? streamingPhase : null,
                  );
                  return Padding(
                    key: message is LoadingMessage
                        ? const ValueKey('loading')
                        : _keyFor(message.id),
                    padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
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
  }
}
