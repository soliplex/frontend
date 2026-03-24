import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';

import '../../auth/server_entry.dart';
import '../room_state.dart';
import '../thread_list_state.dart';
import '../thread_view_state.dart';
import 'message_timeline.dart';
import 'thread_sidebar.dart';

const double _sidebarWidth = 260;
const double _wideBreakpoint = 600;

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.threadId,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String? threadId;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late RoomState _state;
  void Function()? _autoSelectUnsub;

  @override
  void initState() {
    super.initState();
    _state = RoomState(
      connection: widget.serverEntry.connection,
      roomId: widget.roomId,
    );
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
      _state = RoomState(
        connection: widget.serverEntry.connection,
        roomId: widget.roomId,
      );
      if (widget.threadId != null) {
        _state.selectThread(widget.threadId!);
      } else {
        _autoSelectFirstThread();
      }
    } else if (widget.threadId != oldWidget.threadId) {
      if (widget.threadId != null) {
        _cancelAutoSelect();
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

    _autoSelectUnsub = _state.threadList.threads.subscribe((status) {
      if (status is ThreadsLoaded && status.threads.isNotEmpty) {
        _cancelAutoSelect();
        _state.selectThread(status.threads.first.id);
        setState(() {});
      }
    });
  }

  void _cancelAutoSelect() {
    _autoSelectUnsub?.call();
    _autoSelectUnsub = null;
  }

  @override
  void dispose() {
    _cancelAutoSelect();
    _state.dispose();
    super.dispose();
  }

  void _onBackToLobby() => context.go('/lobby');

  void _onThreadSelected(String threadId) {
    _state.selectThread(threadId);
    setState(() {});
    context.go(
      '/room/${widget.serverEntry.alias}/${widget.roomId}/$threadId',
    );
  }

  @override
  Widget build(BuildContext context) {
    final threadListStatus = _state.threadList.threads.watch(context);
    final selectedThreadId = _state.activeThreadView?.threadId;

    return LayoutBuilder(
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
            title: Text(
              selectedThreadId != null ? 'Thread' : widget.roomId,
            ),
          ),
          drawer: Drawer(child: SafeArea(child: sidebar)),
          body: content,
        );
      },
    );
  }

  Widget _buildContent() {
    final threadView = _state.activeThreadView;
    if (threadView == null) {
      return const Center(child: Text('Select a thread'));
    }
    final status = threadView.messages.watch(context);
    return switch (status) {
      MessagesLoading() => const Center(child: CircularProgressIndicator()),
      MessagesFailed(:final error) => Center(
          child: Text('Failed to load messages: $error'),
        ),
      MessagesLoaded(:final messages, :final messageStates) =>
        MessageTimeline(messages: messages, messageStates: messageStates),
    };
  }
}
