import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show RagDocument, Room, SourceReferenceFormatting, buildDocumentFilter;
import '../../auth/server_entry.dart';
import '../document_selections.dart';
import '../pick_file.dart';
import '../../diagnostics/diagnostics_providers.dart';
import '../../diagnostics/models/http_event_grouper.dart';
import '../../diagnostics/models/run_event_filter.dart';
import '../../diagnostics/ui/run_http_detail_page.dart';
import '../agent_runtime_manager.dart';
import '../room_state.dart';
import '../run_registry.dart';
import '../thread_list_state.dart';
import '../thread_view_state.dart';
import '../compute_display_messages.dart';
import 'chat_input.dart';
import 'chunk_visualization_page.dart';
import 'document_picker.dart';
import 'error_retry_panel.dart';
import 'message_timeline.dart';
import 'async_action_dialog.dart';
import 'room_welcome.dart';
import 'thread_sidebar.dart';
import '../upload_tracker.dart';

const double _sidebarWidth = 300;
const double _wideBreakpoint = 600;

/// Builds the label for the file indicator chip in the room header.
///
/// Shows separate counts for room and thread uploads.
String uploadChipLabel(int roomCount, int threadCount) {
  if (roomCount > 0 && threadCount > 0) {
    return '$roomCount room \u00b7 $threadCount thread';
  }
  if (roomCount > 0) return '$roomCount room';
  return '$threadCount thread';
}

class RoomScreen extends StatefulWidget {
  const RoomScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.threadId,
    required this.runtimeManager,
    required this.registry,
    this.enableDocumentFilter = false,
    required this.documentSelections,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String? threadId;
  final AgentRuntimeManager runtimeManager;
  final RunRegistry registry;
  final bool enableDocumentFilter;
  final DocumentSelections documentSelections;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late RoomState _state;
  void Function()? _autoSelectUnsub;
  final _chatController = TextEditingController();
  final _chatFocusNode = FocusNode();
  bool _filesExpanded = false;

  bool get _filterEnabled => widget.enableDocumentFilter;

  DocumentSelections get _documentSelections => widget.documentSelections;

  Set<RagDocument> get _selectedDocuments => _filterEnabled
      ? _documentSelections.get(widget.roomId, widget.threadId)
      : const {};

  void _updateSelection(Set<RagDocument> selection) {
    setState(() {
      _documentSelections.set(widget.roomId, widget.threadId, selection);
    });
  }

  Future<void> _openDocumentPicker() async {
    final roomId = widget.roomId;
    final threadId = widget.threadId;
    final result = await showDocumentPicker(
      context: context,
      fetchDocuments: () =>
          widget.serverEntry.connection.api.getDocuments(roomId),
      selected: _documentSelections.get(roomId, threadId),
    );
    if (result != null && mounted) {
      setState(() {
        _documentSelections.set(roomId, threadId, result);
      });
    }
  }

  // TODO: If a selected document is deleted server-side before send,
  // the backend silently returns empty results. Consider reconciling
  // selections against the fetched document list.
  Map<String, dynamic>? _buildStateOverlay() {
    if (!_filterEnabled) return null;
    final selected = _selectedDocuments;
    return {
      'rag': <String, dynamic>{
        'document_filter':
            selected.isEmpty ? null : buildDocumentFilter(selected.toList()),
      },
    };
  }

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
        if (_filterEnabled && oldWidget.threadId == null) {
          _documentSelections.migrateToThread(widget.roomId, widget.threadId!);
        }
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
      _navigateToThread(current.threads.first.id, replace: true);
      return;
    }

    final targetState = _state;
    _autoSelectUnsub = _state.threadList.threads.subscribe((status) {
      if (!mounted || targetState != _state) return;
      if (status is ThreadsLoaded && status.threads.isNotEmpty) {
        _cancelAutoSelect();
        _navigateToThread(status.threads.first.id, replace: true);
      }
    });
  }

  RoomState _createRoomState() => RoomState(
        connection: widget.serverEntry.connection,
        roomId: widget.roomId,
        runtimeManager: widget.runtimeManager,
        registry: widget.registry,
        onNavigateToThread: (id) => _navigateToThread(id),
      );

  void _navigateToThread(String? threadId, {bool replace = false}) {
    if (!mounted) return;
    final base = '/room/${widget.serverEntry.alias}/${widget.roomId}';
    final path = threadId != null ? '$base/thread/$threadId' : base;
    if (replace || widget.threadId == null) {
      context.replace(path);
    } else {
      context.go(path);
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

  Future<void> _pickAndUploadToRoom(Room room) async {
    final file = await pickFile();
    if (file == null || !mounted) return;
    _state.uploadTracker.uploadToRoom(
      api: widget.serverEntry.connection.api,
      roomId: widget.roomId,
      filename: file.name,
      fileBytes: file.bytes,
      mimeType: file.mimeType,
    );
  }

  Future<void> _pickAndUploadToThread(Room room, String threadId) async {
    final file = await pickFile();
    if (file == null || !mounted) return;
    _state.uploadTracker.uploadToThread(
      api: widget.serverEntry.connection.api,
      roomId: widget.roomId,
      threadId: threadId,
      filename: file.name,
      fileBytes: file.bytes,
      mimeType: file.mimeType,
    );
  }

  Future<void> _pickAndUploadToNewThread(Room room) async {
    final file = await pickFile();
    if (file == null || !mounted) return;

    final threadId = await _state.createThread();
    if (threadId == null || !mounted) return;

    _state.uploadTracker.uploadToThread(
      api: widget.serverEntry.connection.api,
      roomId: widget.roomId,
      threadId: threadId,
      filename: file.name,
      fileBytes: file.bytes,
      mimeType: file.mimeType,
    );
  }

  void _onThreadSelected(String threadId) {
    context.go(
      '/room/${widget.serverEntry.alias}/${widget.roomId}/thread/$threadId',
    );
  }

  void _onQuizTapped(String quizId) {
    final alias = widget.serverEntry.alias;
    context.go('/room/$alias/${widget.roomId}/quiz/$quizId');
  }

  Future<void> _showRenameDialog(String threadId, String currentName) async {
    await showDialog<void>(
      context: context,
      builder: (_) => RenameDialog(
        initialName: currentName,
        onAction: (name) => _state.threadList.renameThread(threadId, name),
      ),
    );
  }

  Future<void> _showDeleteDialog(String threadId) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AsyncActionDialog(
        title: 'Delete Thread',
        contentBuilder: (_) =>
            const Text('Delete this thread? This cannot be undone.'),
        actionLabel: 'Delete',
        isDestructive: true,
        onAction: () => _state.deleteThread(threadId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final threadListStatus = _state.threadList.threads.watch(context);
    final selectedThreadId = _state.activeThreadView?.threadId;
    final roomStatus = _state.room.watch(context);
    final room = roomStatus is RoomLoaded ? roomStatus.room : null;
    final roomName = room?.name ?? widget.roomId;

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
            roomName: roomName,
            onRetryThreads: () => _state.threadList.refresh(),
            quizzes: room?.quizzes ?? const {},
            onQuizTapped: _onQuizTapped,
            onRenameThread: _showRenameDialog,
            onDeleteThread: _showDeleteDialog,
          );
          final content = _buildContent(room);

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
              title: Text(roomName),
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
                    roomName: roomName,
                    onRetryThreads: () => _state.threadList.refresh(),
                    quizzes: room?.quizzes ?? const {},
                    onQuizTapped: _onQuizTapped,
                    onRenameThread: (id, name) {
                      Navigator.pop(drawerContext);
                      _showRenameDialog(id, name);
                    },
                    onDeleteThread: (id) {
                      Navigator.pop(drawerContext);
                      _showDeleteDialog(id);
                    },
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

  Widget _buildContent(Room? room) {
    final threadView = _state.activeThreadView;
    final attachEnabled = room?.enableAttachments ?? false;

    final roomEntries = attachEnabled
        ? _state.uploadTracker.roomUploads(widget.roomId).watch(context)
        : <UploadEntry>[];
    final threadId = threadView?.threadId;
    final threadEntries = attachEnabled && threadId != null
        ? _state.uploadTracker
            .threadUploads(widget.roomId, threadId)
            .watch(context)
        : <UploadEntry>[];

    return Column(
      children: [
        _buildRoomHeader(
          room,
          attachEnabled,
          roomEntries,
          threadEntries,
        ),
        if (_filesExpanded) _buildFilePanel(roomEntries, threadEntries),
        Expanded(
          child: threadView == null
              ? _buildNoThreadBody(room)
              : _buildThreadBody(threadView, room),
        ),
      ],
    );
  }

  Widget _buildRoomHeader(
    Room? room,
    bool attachEnabled,
    List<UploadEntry> roomEntries,
    List<UploadEntry> threadEntries,
  ) {
    final theme = Theme.of(context);
    final roomName = room?.name ?? widget.roomId;
    final allEntries = [...roomEntries, ...threadEntries];
    final hasFiles = allEntries.isNotEmpty;
    final anyUploading = allEntries.any((e) => e.status is UploadUploading);
    final anyFailed = allEntries.any((e) => e.status is UploadError);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              roomName,
              style: theme.textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (hasFiles)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _filesExpanded = !_filesExpanded),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (anyUploading)
                    SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: theme.colorScheme.primary,
                      ),
                    )
                  else if (anyFailed)
                    Icon(
                      Icons.error_outline,
                      size: 16,
                      color: theme.colorScheme.error,
                    )
                  else
                    Icon(
                      Icons.attach_file,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                  const SizedBox(width: 4),
                  Text(
                    _chipLabel(
                      roomEntries.length,
                      threadEntries.length,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: anyFailed
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary,
                    ),
                  ),
                  Icon(
                    _filesExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: anyFailed
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          if (attachEnabled && room != null)
            IconButton(
              icon: const Icon(Icons.upload_file, size: 20),
              tooltip: 'Upload file to room',
              onPressed: () => _pickAndUploadToRoom(room),
            ),
        ],
      ),
    );
  }

  String _chipLabel(int roomCount, int threadCount) =>
      uploadChipLabel(roomCount, threadCount);

  Widget _buildFilePanel(
    List<UploadEntry> roomEntries,
    List<UploadEntry> threadEntries,
  ) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (roomEntries.isNotEmpty) ...[
              Text(
                'Room',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              for (final e in roomEntries) _buildFileRow(e),
            ],
            if (roomEntries.isNotEmpty && threadEntries.isNotEmpty)
              const Divider(height: 12),
            if (threadEntries.isNotEmpty) ...[
              Text(
                'Thread',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
              for (final e in threadEntries) _buildFileRow(e),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFileRow(UploadEntry entry) {
    final theme = Theme.of(context);
    final (icon, color) = switch (entry.status) {
      UploadUploading() => (null, theme.colorScheme.primary),
      UploadSuccess() => (
          Icons.check_circle_outline,
          theme.colorScheme.primary
        ),
      UploadError() => (Icons.error_outline, theme.colorScheme.error),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 16, color: color)
          else
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: color,
              ),
            ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.filename,
                  style: theme.textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis,
                ),
                if (entry.status is UploadError)
                  Text(
                    (entry.status as UploadError).message,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (entry.status is! UploadUploading)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              onPressed: () => _state.uploadTracker.dismiss(entry.id),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildNoThreadBody(Room? room) {
    final roomError = _state.lastError.watch(context);
    final sessionState = _state.sessionState.watch(context);
    _restoreUnsentText(roomError?.unsentText);

    return Column(
      children: [
        Expanded(
          child: RoomWelcome(
            room: room,
            onSuggestionTapped: sessionState != null
                ? null
                : (suggestion) => _state.sendToNewThread(
                      suggestion,
                      stateOverlay: _buildStateOverlay(),
                    ),
            onQuizTapped: _onQuizTapped,
            fallback: const Center(child: Text('Select a thread')),
          ),
        ),
        if (roomError != null)
          _SendErrorBanner(
            error: roomError,
            onDismiss: _state.clearError,
          ),
        ChatInput(
          onSend: (text) => _state.sendToNewThread(
            text,
            stateOverlay: _buildStateOverlay(),
          ),
          onCancel: _state.cancelSpawn,
          sessionState: _state.sessionState,
          controller: _chatController,
          focusNode: _chatFocusNode,
          selectedDocuments: _selectedDocuments,
          onFilterTap: _filterEnabled ? _openDocumentPicker : null,
          onDocumentRemoved: _filterEnabled
              ? (doc) => _updateSelection(
                    Set.of(_selectedDocuments)..remove(doc),
                  )
              : null,
          onAttachFile: (room?.enableAttachments ?? false) && room != null
              ? () => _pickAndUploadToNewThread(room)
              : null,
        ),
      ],
    );
  }

  Widget _buildThreadBody(ThreadViewState threadView, Room? room) {
    final status = threadView.messages.watch(context);
    final streaming = threadView.streamingState.watch(context);
    final sendError = threadView.lastSendError.watch(context);
    final attachEnabled = room?.enableAttachments ?? false;

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
              computeDisplayMessages(messages, streaming).isEmpty
                  ? RoomWelcome(
                      room: room,
                      onSuggestionTapped: (suggestion) =>
                          threadView.sendMessage(
                        suggestion,
                        _state.runtime,
                        stateOverlay: _buildStateOverlay(),
                      ),
                      onQuizTapped: _onQuizTapped,
                      fallback: _threadEmptyFallback(context),
                    )
                  : MessageTimeline(
                      key: ValueKey(threadView.threadId),
                      messages: messages,
                      messageStates: messageStates,
                      streamingState: streaming,
                      executionTrackers: threadView.executionTrackers,
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
                      onShowChunkVisualization: (ref) =>
                          ChunkVisualizationPage.show(
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
          onSend: (text) => threadView.sendMessage(
            text,
            _state.runtime,
            stateOverlay: _buildStateOverlay(),
          ),
          onCancel: threadView.cancelRun,
          sessionState: threadView.sessionState,
          controller: _chatController,
          focusNode: _chatFocusNode,
          enabled: status is MessagesLoaded,
          selectedDocuments: _selectedDocuments,
          onFilterTap: _filterEnabled ? _openDocumentPicker : null,
          onDocumentRemoved: _filterEnabled
              ? (doc) => _updateSelection(
                    Set.of(_selectedDocuments)..remove(doc),
                  )
              : null,
          onAttachFile: attachEnabled && room != null
              ? () => _pickAndUploadToThread(room, threadView.threadId)
              : null,
        ),
      ],
    );
  }

  static Widget _threadEmptyFallback(BuildContext context) {
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
