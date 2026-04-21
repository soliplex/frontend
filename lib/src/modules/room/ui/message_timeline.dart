import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../compute_display_messages.dart';
import '../execution_tracker.dart';
import '../tracker_registry.dart' show awaitingTrackerKey;
import '../run_id_resolver.dart';
import '../source_references_resolver.dart';
import 'message_tile.dart';
import 'scroll/anchored_scroll_controller.dart';
import 'scroll/scroll_to_bottom.dart';

class MessageTimeline extends StatefulWidget {
  const MessageTimeline({
    super.key,
    required this.roomId,
    required this.messages,
    required this.messageStates,
    this.streamingState,
    this.executionTrackers = const {},
    this.onFeedbackSubmit,
    this.onInspect,
    this.onShowChunkVisualization,
  });

  final String roomId;
  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;
  final StreamingState? streamingState;
  final Map<String, ExecutionTracker> executionTrackers;
  final void Function(String runId, FeedbackType feedback, String? reason)?
      onFeedbackSubmit;
  final void Function(String runId)? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;

  @override
  State<MessageTimeline> createState() => _MessageTimelineState();
}

class _MessageTimelineState extends State<MessageTimeline> {
  late final AnchoredScrollController _scrollController;
  late final ScrollToBottomController _scrollToBottomController;

  final Map<String, GlobalKey> _messageKeys = {};
  String? _lastUserMessageId;
  bool _needsInitialScroll = true;

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

    final renderObject = key!.currentContext!.findRenderObject()!;
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

    if (_needsInitialScroll) {
      _needsInitialScroll = false;
      _lastUserMessageId = _findLastUserMessage(widget.messages)?.id;
      _scrollToBottom();
    }

    final streamingActivity = widget.streamingState != null
        ? switch (widget.streamingState!) {
            AwaitingText(:final currentActivity) => currentActivity,
            TextStreaming(:final currentActivity) => currentActivity,
          }
        : null;

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.builder(
                itemCount: displayMessages.length,
                itemBuilder: (context, index) {
                  final message = displayMessages[index];
                  final isLastItem = index == displayMessages.length - 1;
                  // A distinct key for the loading sentinel is load-bearing:
                  // it forces a remount at the AwaitingText → TextStreaming
                  // transition so execution/thinking child widgets can
                  // re-bind their MessageExpansion handle under the real
                  // messageId. Unifying these keys would break persistence.
                  return Padding(
                    key: message is LoadingMessage
                        ? const ValueKey('loading')
                        : _keyFor(message.id),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: MessageTile(
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
                      onShowChunkVisualization: widget.onShowChunkVisualization,
                      executionTracker: widget.executionTrackers[message.id] ??
                          (message is LoadingMessage
                              ? widget.executionTrackers[awaitingTrackerKey]
                              : null),
                      streamingActivity: isLastItem ? streamingActivity : null,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: ScrollToBottomButton(
            controller: _scrollToBottomController,
            onPressed: _onScrollToBottom,
          ),
        ),
      ],
    );
  }
}
