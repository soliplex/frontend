import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../../auth/server_entry.dart';
import '../agent_runtime_manager.dart';
import '../room_state.dart';
import '../thread_list_state.dart';
import '../thread_view_state.dart';
import 'chat_input.dart';
import 'message_timeline.dart';
import 'thread_sidebar.dart';

const double _sidebarWidth = 260;
const double _wideBreakpoint = 600;

final ReadonlySignal<AgentSessionState?> _noSessionState =
    signal<AgentSessionState?>(null);

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.threadId,
    required this.runtimeManager,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String? threadId;
  final AgentRuntimeManager runtimeManager;

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
        onNavigateToThread: _navigateToThread,
      );

  void _navigateToThread(String threadId) {
    if (mounted) {
      context.go(
        '/room/${widget.serverEntry.alias}/${widget.roomId}/$threadId',
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
    _state.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_chatFocusNode.hasFocus) return KeyEventResult.ignored;
    final char = event.character;
    if (char == null || char.isEmpty) return KeyEventResult.ignored;
    // Ignore control characters (e.g. backspace, escape).
    if (char.codeUnitAt(0) < 0x20) return KeyEventResult.ignored;

    _chatFocusNode.requestFocus();
    _chatController.text += char;
    _chatController.selection =
        TextSelection.collapsed(offset: _chatController.text.length);
    return KeyEventResult.handled;
  }

  void _onBackToLobby() => context.go('/lobby');

  void _onThreadSelected(String threadId) {
    context.go(
      '/room/${widget.serverEntry.alias}/${widget.roomId}/$threadId',
    );
  }

  @override
  Widget build(BuildContext context) {
    final threadListStatus = _state.threadList.threads.watch(context);
    final selectedThreadId = _state.activeThreadView?.threadId;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;
          final sidebar = ThreadSidebar(
            threadListStatus: threadListStatus,
            selectedThreadId: selectedThreadId,
            onThreadSelected: _onThreadSelected,
            onBackToLobby: _onBackToLobby,
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

  Widget _buildContent() {
    final threadView = _state.activeThreadView;
    if (threadView == null) {
      return Column(
        children: [
          const Expanded(child: Center(child: Text('Select a thread'))),
          ChatInput(
            onSend: (text) => _state.sendToNewThread(text),
            onCancel: () {},
            sessionState: _noSessionState,
            controller: _chatController,
            focusNode: _chatFocusNode,
          ),
        ],
      );
    }
    final status = threadView.messages.watch(context);
    final streaming = threadView.streamingState.watch(context);
    return Column(
      children: [
        Expanded(
          child: switch (status) {
            MessagesLoading() => const Center(
                child: CircularProgressIndicator(),
              ),
            MessagesFailed(:final error) => Center(
                child: Text('Failed to load messages: $error'),
              ),
            MessagesLoaded(:final messages, :final messageStates) =>
              MessageTimeline(
                messages: messages,
                messageStates: messageStates,
                streamingState: streaming,
              ),
          },
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
