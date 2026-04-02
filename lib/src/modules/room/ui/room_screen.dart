import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show SourceReferenceFormatting;
import '../../auth/server_entry.dart';
import '../../diagnostics/diagnostics_providers.dart';
import '../../diagnostics/models/http_event_grouper.dart';
import '../../diagnostics/models/run_event_filter.dart';
import '../../diagnostics/ui/run_http_detail_page.dart';
import '../agent_runtime_manager.dart';
import '../room_state.dart';
import '../run_registry.dart';
import '../thread_list_state.dart';
import '../thread_view_state.dart';
import 'chat_input.dart';
import 'chunk_visualization_page.dart';
import 'error_retry_panel.dart';
import 'message_timeline.dart';
import 'room_welcome.dart';
import 'thread_sidebar.dart';

const double _sidebarWidth = 300;
const double _wideBreakpoint = 600;

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.threadId,
    required this.runtimeManager,
    required this.registry,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String? threadId;
  final AgentRuntimeManager runtimeManager;
  final RunRegistry registry;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late RoomState _state;
  void Function()? _autoSelectUnsub;
  final _chatController = TextEditingController();
  final _chatFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
    _state = _createRoomState();
    if (widget.threadId != null) {
      _state.selectThread(widget.threadId!);
    } else {
      _autoSelectFirstThread();
    }
  }

  @override
  void didUpdateWidget(RoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.roomId != oldWidget.roomId ||
        widget.serverEntry.serverId != oldWidget.serverEntry.serverId) {
      _cancelAutoSelect();
      _state.dispose();
      _chatController.clear();
      _state = _createRoomState();
      if (widget.threadId != null) {
        _state.selectThread(widget.threadId!);
      } else {
        _autoSelectFirstThread();
      }
    } else if (widget.threadId != oldWidget.threadId) {
      if (widget.threadId != null) {
        _cancelAutoSelect();
        _chatController.clear();
        _state.selectThread(widget.threadId!);
        setState(() {});
      } else {
        _autoSelectFirstThread();
      }
    }
  }

  void _autoSelectFirstThread() {
    final current = _state.threadList.threads.value;
    if (current is ThreadsLoaded && current.threads.isNotEmpty) {
      _state.selectThread(current.threads.first.id);
      setState(() {});
      return;
    }

    final targetState = _state;
    _autoSelectUnsub = _state.threadList.threads.subscribe((status) {
      if (!mounted || targetState != _state) return;
      if (status is ThreadsLoaded && status.threads.isNotEmpty) {
        _cancelAutoSelect();
        _state.selectThread(status.threads.first.id);
        setState(() {});
      }
    });
  }

  RoomState _createRoomState() => RoomState(
        connection: widget.serverEntry.connection,
        roomId: widget.roomId,
        runtimeManager: widget.runtimeManager,
        registry: widget.registry,
        onNavigateToThread: _navigateToThread,
      );

  void _navigateToThread(String threadId) {
    if (mounted) {
      context.go(
        '/room/${widget.serverEntry.alias}/${widget.roomId}/thread/$threadId',
      );
    }
  }

  void _cancelAutoSelect() {
    _autoSelectUnsub?.call();
    _autoSelectUnsub = null;
  }

  @override
  void dispose() {
    _cancelAutoSelect();
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _state.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (_chatFocusNode.hasFocus) return false;
    if (event is! KeyDownEvent) return false;
    if (ModalRoute.of(context)?.isCurrent != true) return false;
    _chatFocusNode.requestFocus();
    return false;
  }

  void _onBackToLobby() => context.go('/lobby');

  void _onNetworkInspector() => context.push('/diagnostics/network');

  void _onRoomInfo() {
    context.push('/room/${widget.serverEntry.alias}/${widget.roomId}/info');
  }

  void _onThreadSelected(String threadId) {
    context.go(
      '/room/${widget.serverEntry.alias}/${widget.roomId}/thread/$threadId',
    );
  }

  @override
  Widget build(BuildContext context) {
    final threadListStatus = _state.threadList.threads.watch(context);
    final selectedThreadId = _state.activeThreadView?.threadId;

    return Focus(
      autofocus: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;
          final sidebar = ThreadSidebar(
            threadListStatus: threadListStatus,
            selectedThreadId: selectedThreadId,
            onThreadSelected: _onThreadSelected,
            onBackToLobby: _onBackToLobby,
            onCreateThread: _state.createThread,
            onNetworkInspector: _onNetworkInspector,
            onRoomInfo: _onRoomInfo,
            onRetryThreads: () => _state.threadList.refresh(),
          );
          final content = _buildContent();

          if (isWide) {
            return Scaffold(
              body: Row(
                children: [
                  SizedBox(width: _sidebarWidth, child: sidebar),
                  const VerticalDivider(width: 1),
                  Expanded(child: content),
                ],
              ),
            );
          }

          return Scaffold(
            appBar: AppBar(
              leading: Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.menu),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
              title: Text(widget.roomId),
            ),
            drawer: Drawer(
              child: Builder(
                builder: (drawerContext) => SafeArea(
                  child: ThreadSidebar(
                    threadListStatus: threadListStatus,
                    selectedThreadId: selectedThreadId,
                    onThreadSelected: (threadId) {
                      Navigator.pop(drawerContext);
                      _onThreadSelected(threadId);
                    },
                    onBackToLobby: _onBackToLobby,
                    onCreateThread: () {
                      Navigator.pop(drawerContext);
                      _state.createThread();
                    },
                    onNetworkInspector: () {
                      Navigator.pop(drawerContext);
                      _onNetworkInspector();
                    },
                    onRoomInfo: () {
                      Navigator.pop(drawerContext);
                      _onRoomInfo();
                    },
                    onRetryThreads: () => _state.threadList.refresh(),
                  ),
                ),
              ),
            ),
            body: content,
          );
        },
      ),
    );
  }

  void _restoreUnsentText(String? unsentText) {
    if (unsentText == null || _chatController.text.isNotEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _chatController.text = unsentText;
      _chatController.selection =
          TextSelection.collapsed(offset: _chatController.text.length);
    });
  }

  Widget _buildContent() {
    final threadView = _state.activeThreadView;
    if (threadView == null) {
      return _buildNoThreadContent();
    }
    return _buildThreadContent(threadView);
  }

  Widget _buildNoThreadContent() {
    final roomError = _state.lastError.watch(context);
    final sessionState = _state.sessionState.watch(context);
    _restoreUnsentText(roomError?.unsentText);

    return Column(
      children: [
        Expanded(
          child: Builder(
            builder: (context) {
              final roomStatus = _state.room.watch(context);
              final room = roomStatus is RoomLoaded ? roomStatus.room : null;
              return RoomWelcome(
                room: room,
                onSuggestionTapped: sessionState != null
                    ? null
                    : (suggestion) => _state.sendToNewThread(suggestion),
                fallback: const Center(child: Text('Select a thread')),
              );
            },
          ),
        ),
        if (roomError != null)
          _SendErrorBanner(
            error: roomError,
            onDismiss: _state.clearError,
          ),
        ChatInput(
          onSend: (text) => _state.sendToNewThread(text),
          onCancel: _state.cancelSpawn,
          sessionState: _state.sessionState,
          controller: _chatController,
          focusNode: _chatFocusNode,
        ),
      ],
    );
  }

  Widget _buildThreadContent(ThreadViewState threadView) {
    final status = threadView.messages.watch(context);
    final streaming = threadView.streamingState.watch(context);
    final roomStatus = _state.room.watch(context);
    final room = roomStatus is RoomLoaded ? roomStatus.room : null;
    final sendError = threadView.lastSendError.watch(context);

    _restoreUnsentText(sendError?.unsentText);

    return Column(
      children: [
        Expanded(
          child: switch (status) {
            MessagesLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            MessagesFailed(:final error) => ErrorRetryPanel(
                title: 'Failed to load messages',
                error: error,
                onRetry: threadView.refresh,
              ),
            MessagesLoaded(:final messages, :final messageStates) =>
              MessageTimeline(
                messages: messages,
                messageStates: messageStates,
                streamingState: streaming,
                executionTrackers: threadView.executionTrackers,
                room: room,
                onSuggestionTapped: (suggestion) =>
                    threadView.sendMessage(suggestion, _state.runtime),
                onFeedbackSubmit: threadView.submitFeedback,
                onInspect: (runId) {
                  final inspector = ProviderScope.containerOf(context)
                      .read(networkInspectorProvider);
                  final filtered = filterEventsByRunId(
                    inspector.events,
                    runId,
                  );
                  final groups = groupHttpEvents(filtered);
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RunHttpDetailPage(groups: groups),
                    ),
                  );
                },
                onShowChunkVisualization: (ref) => ChunkVisualizationPage.show(
                  context: context,
                  api: widget.serverEntry.connection.api,
                  roomId: widget.roomId,
                  chunkId: ref.chunkId,
                  documentTitle: ref.displayTitle,
                  pageNumbers: ref.pageNumbers,
                ),
              ),
          },
        ),
        if (sendError != null)
          _SendErrorBanner(
            error: sendError,
            onDismiss: () => threadView.clearSendError(),
          ),
        ChatInput(
          onSend: (text) => threadView.sendMessage(text, _state.runtime),
          onCancel: threadView.cancelRun,
          sessionState: threadView.sessionState,
          controller: _chatController,
          focusNode: _chatFocusNode,
        ),
      ],
    );
  }
}

class _SendErrorBanner extends StatelessWidget {
  const _SendErrorBanner({required this.error, required this.onDismiss});

  final SendError error;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error.error.toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}
