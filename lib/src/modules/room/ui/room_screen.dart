import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        CancelToken,
        MalformedResponseException,
        RagDocument,
        ReconnectFailed,
        ReconnectStatus,
        Reconnected,
        Reconnecting,
        Room,
        SourceReferenceFormatting,
        buildDocumentFilter;
import '../../../core/routes.dart';
import '../../auth/return_to_storage.dart';
import '../../auth/server_entry.dart';
import '../document_selections.dart';
import '../pick_file.dart';
import '../agent_runtime_manager.dart';
import '../room_state.dart';
import '../run_registry.dart';
import '../thread_list_state.dart';
import '../thread_view_state.dart';
import '../compute_display_messages.dart';
import '../workdir_controller.dart';
import 'approval_handler.dart';
import 'chat_input.dart';
import 'chunk_visualization_page.dart';
import 'document_picker.dart';
import 'error_retry_panel.dart';
import 'message_timeline.dart';
import 'async_action_dialog.dart';
import 'room_welcome.dart';
import 'thread_sidebar.dart';
import 'upload_event_banner.dart';
import '../upload_tracker.dart';
import '../upload_tracker_registry.dart';
import 'package:soliplex_design/soliplex_design.dart';

const double _sidebarWidth = 300;
const double _wideBreakpoint = 600;

/// Builds the label for the file indicator chip in the room header.
///
/// Shows separate counts for room and thread uploads. At least one
/// count must be positive.
String uploadChipLabel(int roomCount, int threadCount) {
  assert(roomCount > 0 || threadCount > 0);
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
    required this.uploadRegistry,
    this.enableDocumentFilter = false,
    required this.documentSelections,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final String? threadId;
  final AgentRuntimeManager runtimeManager;
  final RunRegistry registry;
  final UploadTrackerRegistry uploadRegistry;
  final bool enableDocumentFilter;
  final DocumentSelections documentSelections;

  @override
  State<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends State<RoomScreen> {
  late RoomState _state;
  late WorkdirController _workdirs;
  void Function()? _autoSelectUnsub;
  final _chatController = TextEditingController();
  final _chatFocusNode = FocusNode();
  bool _filesExpanded = false;

  bool get _filterEnabled => widget.enableDocumentFilter;

  /// Whether the room exposes any filterable documents/datasets. Resolved
  /// asynchronously by [_refreshFilterableDocuments]; starts `false` so the
  /// filter button pops in once a non-empty corpus is confirmed rather than
  /// flashing and disappearing for empty rooms.
  bool _hasFilterableDocuments = false;

  /// Set when the document fetch fails. We can't tell whether the room has a
  /// corpus, so the filter button stays visible to avoid stripping the
  /// affordance on a transient network error — the picker handles its own
  /// retry.
  bool _filterDocsLoadFailed = false;

  CancelToken? _filterDocsCancelToken;

  /// Show the filter button only when filtering is enabled and there is
  /// something to filter (or we failed to find out).
  bool get _showDocumentFilter =>
      _filterEnabled && (_hasFilterableDocuments || _filterDocsLoadFailed);

  DocumentSelections get _documentSelections => widget.documentSelections;

  Set<RagDocument> get _selectedDocuments => _filterEnabled
      ? _documentSelections.get(widget.roomId, widget.threadId)
      : const {};

  void _updateSelection(Set<RagDocument> selection) {
    setState(() {
      _documentSelections.set(widget.roomId, widget.threadId, selection);
    });
  }

  /// Fetches the room's document corpus to decide whether the filter button
  /// should be shown. No-op when filtering is disabled. Cancels any in-flight
  /// fetch so a room switch can't apply a stale result.
  void _refreshFilterableDocuments() {
    if (!_filterEnabled) return;
    _filterDocsCancelToken?.cancel('refresh');
    final token = CancelToken();
    _filterDocsCancelToken = token;
    widget.serverEntry.connection.api
        .getDocuments(widget.roomId, cancelToken: token)
        .then((docs) {
      if (!mounted || token != _filterDocsCancelToken) return;
      setState(() {
        _hasFilterableDocuments = docs.isNotEmpty;
        _filterDocsLoadFailed = false;
      });
    }).catchError((Object error, StackTrace stackTrace) {
      if (!mounted || token != _filterDocsCancelToken) return;
      dev.log(
        'Failed to load filterable documents',
        error: error,
        stackTrace: stackTrace,
        name: 'RoomScreen',
        level: 1000,
      );
      setState(() => _filterDocsLoadFailed = true);
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
    _workdirs = _createWorkdirController();
    _refreshFilterableDocuments();
    if (widget.threadId != null) {
      _state.selectThread(widget.threadId!);
    } else {
      _autoSelectFirstThread();
    }
    unawaited(_restorePersistedComposer());
  }

  /// Restores a composer draft that was persisted across an
  /// auth-failure redirect for this `(serverId, roomId)`. No-op if
  /// the controller already has text (user typed something since
  /// mount, or another restoration path already populated it).
  ///
  /// Storage failures are logged at SEVERE and swallowed; an empty
  /// composer is the safe fallback.
  Future<void> _restorePersistedComposer() async {
    try {
      final text = await ReturnToStorage.loadComposer(
        serverId: widget.serverEntry.serverId,
        roomId: widget.roomId,
      );
      if (!mounted || text == null) return;
      if (_chatController.text.isNotEmpty) return;
      _chatController.text = text;
      _chatController.selection =
          TextSelection.collapsed(offset: _chatController.text.length);
      // One-shot: clear once restored so subsequent mounts of the same
      // room don't re-pre-fill the box with stale content.
      await ReturnToStorage.clearComposer(
        serverId: widget.serverEntry.serverId,
        roomId: widget.roomId,
      );
    } catch (e, st) {
      dev.log(
        'Failed to restore persisted composer draft',
        error: e,
        stackTrace: st,
        level: 1000,
      );
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
      _workdirs = _createWorkdirController();
      _hasFilterableDocuments = false;
      _filterDocsLoadFailed = false;
      _refreshFilterableDocuments();
      if (widget.threadId != null) {
        _state.selectThread(widget.threadId!);
      } else {
        _autoSelectFirstThread();
      }
    } else if (widget.threadId != oldWidget.threadId) {
      if (widget.threadId != null) {
        _cancelAutoSelect();
        _chatController.clear();
        _workdirs.clearCache();
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
        serverEntry: widget.serverEntry,
        roomId: widget.roomId,
        runtimeManager: widget.runtimeManager,
        registry: widget.registry,
        uploadRegistry: widget.uploadRegistry,
        onNavigateToThread: (id) => _navigateToThread(id),
      );

  WorkdirController _createWorkdirController() => WorkdirController(
        api: widget.serverEntry.connection.api,
        roomId: widget.roomId,
      );

  void _navigateToThread(String? threadId, {bool replace = false}) {
    if (!mounted) return;
    final alias = widget.serverEntry.alias;
    final roomId = widget.roomId;
    final path = threadId != null
        ? AppRoutes.thread(alias, roomId, threadId)
        : AppRoutes.room(alias, roomId);
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
    _filterDocsCancelToken?.cancel('disposed');
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

  void _onBackToLobby() => context.go(AppRoutes.lobby);

  /// Drives the user back through sign-in for this server, returning to the
  /// current room/thread afterward. Reached only if an [AuthException]
  /// surfaces in an error panel despite the funnel-to-redirect path.
  void _onReauthenticate() {
    final alias = widget.serverEntry.alias;
    final roomId = widget.roomId;
    final threadId = widget.threadId;
    final returnTo = threadId != null
        ? AppRoutes.thread(alias, roomId, threadId)
        : AppRoutes.room(alias, roomId);
    context.go(
      AppRoutes.homeWithUrl(
        widget.serverEntry.serverUrl.toString(),
        returnTo: returnTo,
      ),
    );
  }

  void _onNetworkInspector() => context.push(AppRoutes.networkInspector);

  void _onVersions() => context.push(AppRoutes.versions);

  void _onRoomInfo() {
    context.push(
      AppRoutes.roomInfo(widget.serverEntry.alias, widget.roomId),
    );
  }

  Future<List<PickedFile>> _pickWithErrorSurfacing(
    Future<PickFilesResult?> Function() pick, {
    String? threadId,
  }) async {
    final PickFilesResult? result;
    try {
      result = await pick();
    } on PickFilePickerException catch (e, st) {
      if (!mounted) return const [];
      dev.log(
        'Pick failed',
        error: e.cause,
        stackTrace: st,
        name: 'RoomScreen',
        level: 1000,
      );
      _state.uploadTracker.recordClientError(
        roomId: widget.roomId,
        threadId: threadId,
        filename: '(unknown)',
        message: pickerErrorMessage(e.cause),
      );
      return const [];
    }
    if (result == null || !mounted) return const [];
    for (final itemError in result.errors) {
      dev.log(
        'Pick failed for ${itemError.filename}',
        error: itemError.cause,
        name: 'RoomScreen',
        level: 1000,
      );
      _state.uploadTracker.recordClientError(
        roomId: widget.roomId,
        threadId: threadId,
        filename: itemError.filename,
        message: pickerErrorMessage(itemError.cause),
      );
    }
    return result.files;
  }

  void _enqueueUploadsToThread(String threadId, List<PickedFile> files) {
    for (final file in files) {
      _state.uploadTracker.uploadToThread(
        roomId: widget.roomId,
        threadId: threadId,
        filename: file.name,
        openStream: file.openStream,
        contentLength: file.size,
        mimeType: file.mimeType,
        webFileBlob: file.webFileBlob,
      );
    }
  }

  Future<void> _pickAndUploadToThread(
    String threadId,
    Future<PickFilesResult?> Function() pick,
  ) async {
    final files = await _pickWithErrorSurfacing(pick, threadId: threadId);
    if (!mounted) return;
    _enqueueUploadsToThread(threadId, files);
  }

  Future<void> _pickAndUploadToNewThread(
    Future<PickFilesResult?> Function() pick,
  ) async {
    // Read errors before thread creation attach to the room scope
    // since there's no thread yet to route them to.
    final files = await _pickWithErrorSurfacing(pick);
    if (files.isEmpty || !mounted) return;

    final threadId = await _state.createThread();
    if (threadId == null || !mounted) return;

    _enqueueUploadsToThread(threadId, files);
  }

  void _onThreadSelected(String threadId) {
    context.go(
      AppRoutes.thread(widget.serverEntry.alias, widget.roomId, threadId),
    );
  }

  void _onQuizTapped(String quizId) {
    context.go(
      AppRoutes.quiz(widget.serverEntry.alias, widget.roomId, quizId),
    );
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
            onVersions: _onVersions,
            onRoomInfo: _onRoomInfo,
            roomName: roomName,
            onRetryThreads: () => _state.threadList.refresh(),
            onReauthenticate: _onReauthenticate,
            quizzes: room?.quizzes ?? const {},
            onQuizTapped: _onQuizTapped,
            onRenameThread: _showRenameDialog,
            onDeleteThread: _showDeleteDialog,
            runningThreadIds: _state.runningThreadIds,
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
                    onVersions: () {
                      Navigator.pop(drawerContext);
                      _onVersions();
                    },
                    onRoomInfo: () {
                      Navigator.pop(drawerContext);
                      _onRoomInfo();
                    },
                    roomName: roomName,
                    runningThreadIds: _state.runningThreadIds,
                    onRetryThreads: () => _state.threadList.refresh(),
                    onReauthenticate: _onReauthenticate,
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
    final messagesStatus = threadView?.messages.watch(context);

    final UploadsStatus roomStatus = attachEnabled
        ? _state.uploadTracker.roomUploads(widget.roomId).watch(context)
        : const UploadsLoaded(<DisplayUpload>[]);
    final threadId = threadView?.threadId;
    final UploadsStatus threadStatus = attachEnabled && threadId != null
        ? _state.uploadTracker
            .threadUploads(widget.roomId, threadId)
            .watch(context)
        : const UploadsLoaded(<DisplayUpload>[]);

    final body = threadView == null || messagesStatus == null
        ? _buildNoThreadBody(room)
        : _buildThreadBody(threadView, room, messagesStatus);

    return Column(
      children: [
        _buildRoomHeader(room, roomStatus, threadStatus),
        if (_filesExpanded) _buildFilePanel(roomStatus, threadStatus),
        Expanded(child: body),
        _buildChatInput(threadView, room, messagesStatus),
      ],
    );
  }

  Widget _buildRoomHeader(
    Room? room,
    UploadsStatus roomStatus,
    UploadsStatus threadStatus,
  ) {
    final theme = Theme.of(context);
    final roomName = room?.name ?? widget.roomId;
    final chip = _buildChipSegment(roomStatus, threadStatus, theme);

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s4, vertical: SoliplexSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              roomName,
              style: theme.textTheme.titleMedium,
            ),
          ),
          if (chip != null)
            Material(
              color: theme.colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(soliplexRadii.lg),
              clipBehavior: Clip.antiAlias,
              child: chip,
            ),
        ],
      ),
    );
  }

  /// Returns the chip segment, or null to hide it when both scopes
  /// are Loaded-empty.
  Widget? _buildChipSegment(
    UploadsStatus roomStatus,
    UploadsStatus threadStatus,
    ThemeData theme,
  ) {
    final roomFiles = _uploadsOrNull(roomStatus);
    final threadFiles = _uploadsOrNull(threadStatus);

    final anyLoading =
        roomStatus is UploadsLoading || threadStatus is UploadsLoading;
    final anyFailed =
        roomStatus is UploadsFailed || threadStatus is UploadsFailed;

    if (!anyLoading &&
        !anyFailed &&
        (roomFiles == null || roomFiles.isEmpty) &&
        (threadFiles == null || threadFiles.isEmpty)) {
      return null;
    }

    final all = [...?roomFiles, ...?threadFiles];
    final anyPending = all.any((e) => e is PendingUpload);
    final anyUploadFailed = all.any((e) => e is FailedUpload);
    final color = (anyFailed || anyUploadFailed)
        ? theme.colorScheme.error
        : theme.colorScheme.onSecondaryContainer;

    final Widget leading;
    if (anyLoading || anyPending) {
      leading = SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2, color: color),
      );
    } else if (anyFailed || anyUploadFailed) {
      leading = Icon(Icons.error_outline, size: 16, color: color);
    } else {
      leading = Icon(Icons.attach_file, size: 16, color: color);
    }

    final label = (roomFiles != null && threadFiles != null)
        ? uploadChipLabel(roomFiles.length, threadFiles.length)
        : 'Files';

    return InkWell(
      onTap: () => setState(() => _filesExpanded = !_filesExpanded),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            leading,
            const SizedBox(width: SoliplexSpacing.s2),
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
            const SizedBox(width: SoliplexSpacing.s1),
            Icon(
              _filesExpanded ? Icons.expand_less : Icons.expand_more,
              size: 16,
              color: color,
            ),
          ],
        ),
      ),
    );
  }

  List<DisplayUpload>? _uploadsOrNull(UploadsStatus s) =>
      s is UploadsLoaded ? s.uploads : null;

  bool _scopeRendersContent(UploadsStatus s) => switch (s) {
        UploadsLoading() => true,
        UploadsLoaded(uploads: final u) => u.isNotEmpty,
        UploadsFailed() => true,
      };

  Widget _buildFilePanel(
    UploadsStatus roomStatus,
    UploadsStatus threadStatus,
  ) {
    final theme = Theme.of(context);
    final roomFiles = _uploadsOrNull(roomStatus);
    final threadFiles = _uploadsOrNull(threadStatus);
    final bothEmpty = (roomFiles?.isEmpty ?? true) &&
        (threadFiles?.isEmpty ?? true) &&
        roomStatus is UploadsLoaded &&
        threadStatus is UploadsLoaded;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s2),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(SoliplexSpacing.s2),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(soliplexRadii.md),
        ),
        // Cap the popover height so a large file list scrolls inside
        // the panel instead of pushing the chat input off-screen.
        // 40% of the viewport leaves room for the message timeline
        // and the input bar.
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.4,
          ),
          // Right padding reserves space for the overlay scrollbar so
          // it doesn't sit on top of trailing close buttons (cancel /
          // dismiss) on file rows.
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(right: SoliplexSpacing.s3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (bothEmpty)
                  Text(
                    'No files attached.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  )
                else ...[
                  _buildScopeSection('Room', roomStatus, theme),
                  // The divider sits between two visible sections. A
                  // scope is "visible" when it's Loading or Failed
                  // (those render a section row), or Loaded with at
                  // least one file.
                  if (_scopeRendersContent(roomStatus) &&
                      _scopeRendersContent(threadStatus))
                    const Divider(height: 12),
                  _buildScopeSection('Thread', threadStatus, theme),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildScopeSection(
    String label,
    UploadsStatus status,
    ThemeData theme,
  ) {
    return switch (status) {
      UploadsLoading() => Row(
          children: [
            _sectionLabel(label, theme),
            const SizedBox(width: SoliplexSpacing.s2),
            const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ],
        ),
      UploadsLoaded(uploads: final list) when list.isEmpty => const SizedBox(),
      UploadsLoaded(uploads: final list) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _sectionLabel(label, theme),
            for (final entry in list) _buildFileRow(entry),
          ],
        ),
      UploadsFailed(error: final error) => Row(
          children: [
            _sectionLabel(label, theme),
            const SizedBox(width: SoliplexSpacing.s2),
            Expanded(
              child: Text(
                'Failed to load: ${uploadErrorMessage(error)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
    };
  }

  Widget _sectionLabel(String label, ThemeData theme) {
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildFileRow(DisplayUpload entry) {
    final theme = Theme.of(context);
    final isFailed = entry is FailedUpload;
    final (icon, color, errorMessage) = switch (entry) {
      PersistedUpload() => (
          Icons.check_circle_outline,
          theme.colorScheme.primary,
          null,
        ),
      PendingUpload() => (null, theme.colorScheme.primary, null),
      FailedUpload(message: final m) => (
          Icons.error_outline,
          theme.colorScheme.onErrorContainer,
          m,
        ),
    };

    final (closeTooltip, closeAction) = switch (entry) {
      PendingUpload(:final id) => (
          'Cancel upload',
          () => _state.uploadTracker.cancelUpload(id)
        ),
      FailedUpload(:final id) => (
          'Dismiss',
          () => _state.uploadTracker.dismissFailed(id)
        ),
      _ => (null, null),
    };
    final closeColor = isFailed
        ? theme.colorScheme.onErrorContainer
        : theme.colorScheme.outline;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      padding: isFailed
          ? const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1)
          : const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s1, vertical: SoliplexSpacing.s1),
      decoration: isFailed
          ? BoxDecoration(
              color: theme.colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(soliplexRadii.sm),
            )
          : null,
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
                value: switch (entry) {
                  PendingUpload(:final progress) => progress,
                  _ => null,
                },
              ),
            ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.filename,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: isFailed ? theme.colorScheme.onErrorContainer : null,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                if (errorMessage != null)
                  Text(
                    errorMessage,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onErrorContainer,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (closeAction != null)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: closeColor,
              tooltip: closeTooltip,
              onPressed: closeAction,
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
        if (room?.enableAttachments ?? false)
          UploadEventBanner(
            tracker: _state.uploadTracker,
            roomId: widget.roomId,
            threadId: null,
          ),
      ],
    );
  }

  Widget _buildThreadBody(
    ThreadViewState threadView,
    Room? room,
    ThreadViewStatus status,
  ) {
    final streaming = threadView.streamingState.watch(context);
    final sendError = threadView.lastSendError.watch(context);
    final reconnectStatus = threadView.reconnectStatus.watch(context);
    final attachEnabled = room?.enableAttachments ?? false;

    _restoreUnsentText(sendError?.unsentText);

    return Stack(
      children: [
        ApprovalHandler(
          pendingApproval: threadView.pendingApproval,
          onRespond: threadView.respondToApproval,
        ),
        Column(
          children: [
            if (reconnectStatus is Reconnecting ||
                reconnectStatus is Reconnected)
              _ReconnectBanner(
                status: reconnectStatus!,
                onDismiss: threadView.dismissReconnectStatus,
              ),
            Expanded(
              child: switch (status) {
                MessagesLoading() => const Center(
                    child: CircularProgressIndicator(),
                  ),
                MessagesFailed(:final error) => ErrorRetryPanel(
                    title: error is MalformedResponseException
                        ? "Couldn't display thread history"
                        : 'Failed to load messages',
                    error: error,
                    // Shape-drift is a backend bug — retry won't help, so
                    // hide the button rather than misleading the user.
                    onRetry: error is MalformedResponseException
                        ? null
                        : threadView.refresh,
                    onReauthenticate: _onReauthenticate,
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
                          roomId: widget.roomId,
                          messages: messages,
                          messageStates: messageStates,
                          streamingState: streaming,
                          executionTrackers: threadView.executionTrackers,
                          onFeedbackSubmit: threadView.submitFeedback,
                          onInspect: (runId) => context.push(
                            AppRoutes.networkInspectorForRun(runId),
                          ),
                          onShowChunkVisualization: (ref) =>
                              ChunkVisualizationPage.show(
                            context: context,
                            api: widget.serverEntry.connection.api,
                            roomId: widget.roomId,
                            chunkId: ref.chunkId,
                            documentTitle: ref.displayTitle,
                            pageNumbers: ref.pageNumbers,
                          ),
                          onFetchWorkdirFiles: (runId) =>
                              _workdirs.fetchFiles(threadView.threadId, runId),
                          onDownloadWorkdirFile: (runId, file) =>
                              _workdirs.download(
                            threadView.threadId,
                            runId,
                            file,
                          ),
                          onPreviewWorkdirFile: (runId, file) =>
                              _workdirs.fetchBytes(
                            threadView.threadId,
                            runId,
                            file,
                          ),
                        ),
              },
            ),
            if (sendError != null)
              _SendErrorBanner(
                error: sendError,
                onDismiss: () => threadView.clearSendError(),
              ),
            if (attachEnabled)
              UploadEventBanner(
                tracker: _state.uploadTracker,
                roomId: widget.roomId,
                threadId: threadView.threadId,
              ),
          ],
        ),
      ],
    );
  }

  /// Renders the single ChatInput at the bottom of the room layout. Dispatches
  /// callbacks based on whether a [threadView] is active. Using one widget for
  /// both states keeps the [EditableText] element stable across the
  /// welcome → thread transition; see issue #212.
  Widget _buildChatInput(
    ThreadViewState? threadView,
    Room? room,
    ThreadViewStatus? status,
  ) {
    final attachEnabled = room?.enableAttachments ?? false;
    VoidCallback? attachCallback(Future<PickFilesResult?> Function() pick) {
      if (!attachEnabled) return null;
      return threadView != null
          ? () => _pickAndUploadToThread(threadView.threadId, pick)
          : () => _pickAndUploadToNewThread(pick);
    }

    return ChatInput(
      onSend: (text) {
        if (threadView != null) {
          threadView.sendMessage(
            text,
            _state.runtime,
            stateOverlay: _buildStateOverlay(),
          );
        } else {
          _state.sendToNewThread(text, stateOverlay: _buildStateOverlay());
        }
      },
      onCancel: threadView != null ? threadView.cancelRun : _state.cancelSpawn,
      sessionState: threadView?.sessionState ?? _state.sessionState,
      cancelEnabled: threadView?.isCancellable,
      controller: _chatController,
      focusNode: _chatFocusNode,
      enabled: threadView == null || status is MessagesLoaded,
      selectedDocuments: _selectedDocuments,
      onFilterTap: _showDocumentFilter ? _openDocumentPicker : null,
      onDocumentRemoved: _filterEnabled
          ? (doc) => _updateSelection(Set.of(_selectedDocuments)..remove(doc))
          : null,
      onAttachFile: attachCallback(pickFiles),
      onAttachFolder: attachCallback(pickFolder),
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
          const SizedBox(height: SoliplexSpacing.s3),
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
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      color: theme.colorScheme.errorContainer,
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: theme.colorScheme.error),
          const SizedBox(width: SoliplexSpacing.s2),
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

/// Banner for in-flight SSE reconnect lifecycle states.
///
/// Renders [Reconnecting] and [Reconnected] only. Callers must filter
/// out [ReconnectFailed] (which surfaces through the send-error
/// banner) before passing a status to this widget.
class _ReconnectBanner extends StatefulWidget {
  const _ReconnectBanner({required this.status, required this.onDismiss});

  final ReconnectStatus status;
  final VoidCallback onDismiss;

  @override
  State<_ReconnectBanner> createState() => _ReconnectBannerState();
}

class _ReconnectBannerState extends State<_ReconnectBanner> {
  Timer? _autoDismiss;

  @override
  void didUpdateWidget(covariant _ReconnectBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status.runtimeType != widget.status.runtimeType) {
      _autoDismiss?.cancel();
      _autoDismiss = null;
      _scheduleAutoDismissIfNeeded();
    }
  }

  @override
  void initState() {
    super.initState();
    _scheduleAutoDismissIfNeeded();
  }

  void _scheduleAutoDismissIfNeeded() {
    if (widget.status is Reconnected) {
      _autoDismiss = Timer(
        const Duration(seconds: 4),
        () {
          if (!mounted) return;
          widget.onDismiss();
        },
      );
    }
  }

  @override
  void dispose() {
    _autoDismiss?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, label) = switch (widget.status) {
      Reconnecting(:final attempt) => (
          const _SpinnerIcon(),
          'Reconnecting… (attempt $attempt)',
        ),
      Reconnected() => (
          Icon(Icons.check_circle_outline, size: 16, color: scheme.primary),
          'Reconnected.',
        ),
      // Filtered at call site, but exhaustive here so a future
      // ReconnectStatus subclass forces a build break instead of
      // silently rendering an empty banner.
      ReconnectFailed() => (const SizedBox.shrink(), ''),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: SoliplexSpacing.s3, vertical: SoliplexSpacing.s2),
      color: scheme.secondaryContainer,
      child: Row(
        children: [
          icon,
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            onPressed: widget.onDismiss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _SpinnerIcon extends StatelessWidget {
  const _SpinnerIcon();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 14,
      width: 14,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(scheme.primary),
      ),
    );
  }
}
