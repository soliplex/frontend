import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../execution_tracker.dart';
import '../run_id_resolver.dart';
import 'message_tile.dart';
import 'room_welcome.dart';
import 'scroll/anchored_scroll_controller.dart';
import 'scroll/scroll_to_bottom.dart';
import 'streaming_tile.dart';

class MessageTimeline extends StatefulWidget {
  const MessageTimeline({
    super.key,
    required this.messages,
    required this.messageStates,
    this.streamingState,
    this.executionTracker,
    this.room,
    this.onSuggestionTapped,
    this.onFeedbackSubmit,
  });

  final List<ChatMessage> messages;
  final Map<String, MessageState> messageStates;
  final StreamingState? streamingState;
  final ExecutionTracker? executionTracker;
  final Room? room;
  final void Function(String suggestion)? onSuggestionTapped;
  final void Function(String runId, FeedbackType feedback, String? reason)?
      onFeedbackSubmit;

  @override
  State<MessageTimeline> createState() => _MessageTimelineState();
}

class _MessageTimelineState extends State<MessageTimeline> {
  late final AnchoredScrollController _scrollController;
  late final ScrollToBottomController _scrollToBottomController;

  final Map<String, GlobalKey> _messageKeys = {};
  String? _lastUserMessageId;
  bool _needsInitialScroll = true;

  @override
  void initState() {
    super.initState();
    _scrollController = AnchoredScrollController();
    _scrollToBottomController = ScrollToBottomController();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(MessageTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);

    final lastUserMsg = _findLastUserMessage(widget.messages);
    if (lastUserMsg != null && lastUserMsg.id != _lastUserMessageId) {
      _lastUserMessageId = lastUserMsg.id;
      _needsInitialScroll = false;
      _pinMessageAtTop(lastUserMsg.id);
    }

    final activeIds = widget.messages.map((m) => m.id).toSet();
    _messageKeys.removeWhere((id, _) => !activeIds.contains(id));
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
    final hasStreaming = widget.streamingState != null;
    final itemCount = widget.messages.length + (hasStreaming ? 1 : 0);

    if (itemCount == 0) {
      return RoomWelcome(
        room: widget.room,
        onSuggestionTapped: widget.onSuggestionTapped,
        fallback: _emptyFallback(context),
      );
    }

    if (_needsInitialScroll) {
      _needsInitialScroll = false;
      _lastUserMessageId = _findLastUserMessage(widget.messages)?.id;
      _scrollToBottom();
    }

    final runIdMap = buildRunIdMap(widget.messages, widget.messageStates);

    return Stack(
      children: [
        CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.builder(
                itemCount: itemCount,
                itemBuilder: (context, index) {
                  if (hasStreaming && index == widget.messages.length) {
                    return Padding(
                      key: const ValueKey('streaming'),
                      padding: const EdgeInsets.only(bottom: 16),
                      child: StreamingTile(
                        streamingState: widget.streamingState!,
                        executionTracker: widget.executionTracker,
                      ),
                    );
                  }
                  final message = widget.messages[index];
                  return Padding(
                    key: _keyFor(message.id),
                    padding: const EdgeInsets.only(bottom: 16),
                    child: MessageTile(
                      message: message,
                      runId: runIdMap[message.id],
                      onFeedbackSubmit: widget.onFeedbackSubmit,
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

  static Widget _emptyFallback(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 48,
              color: theme.colorScheme.outline.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(
            'Type a message to get started',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
