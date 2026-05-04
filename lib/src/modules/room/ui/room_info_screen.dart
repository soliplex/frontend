import 'dart:async' show unawaited;
import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_client/soliplex_client.dart' hide Room, State;
import '../../../shared/theme_toggle_button.dart';

import '../pick_file.dart';

import '../../../core/routes.dart';
import '../../auth/server_entry.dart';
import '../upload_tracker.dart';
import '../upload_tracker_registry.dart';
import 'room_info/client_tools_card.dart';
import 'room_info/documents_card.dart';
import 'room_info/expandable_list_card.dart';
import 'room_info/features_card.dart';
import 'room_info/quizzes_card.dart';
import 'room_info/room_info_widgets.dart';
import 'room_info/skill_card.dart';
import 'room_info/system_prompt_viewer.dart';
import '../../../../soliplex_frontend.dart';

class RoomInfoScreen extends StatefulWidget {
  const RoomInfoScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.toolRegistryResolver,
    required this.uploadRegistry,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final Future<ToolRegistry> Function(String roomId) toolRegistryResolver;
  final UploadTrackerRegistry uploadRegistry;

  @override
  State<RoomInfoScreen> createState() => _RoomInfoScreenState();
}

class _RoomInfoScreenState extends State<RoomInfoScreen> {
  late CancelToken _cancelToken;
  late Future<Room> _roomFuture;
  late Future<List<RagDocument>> _documentsFuture;
  late Future<List<Tool>> _clientToolsFuture;

  @override
  void initState() {
    super.initState();
    _cancelToken = CancelToken();
    final api = widget.serverEntry.connection.api;
    _roomFuture = api.getRoom(widget.roomId, cancelToken: _cancelToken);
    _documentsFuture =
        api.getDocuments(widget.roomId, cancelToken: _cancelToken)..ignore();
    _clientToolsFuture = widget
        .toolRegistryResolver(widget.roomId)
        .then((r) => r.toolDefinitions);
  }

  @override
  void dispose() {
    _cancelToken.cancel('disposed');
    super.dispose();
  }

  void _retryDocuments() {
    setState(() {
      _cancelToken.cancel('retry');
      _cancelToken = CancelToken();
      _documentsFuture = widget.serverEntry.connection.api
          .getDocuments(widget.roomId, cancelToken: _cancelToken)
        ..ignore();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.adaptive.arrow_back),
          tooltip: 'Back',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go(
                AppRoutes.room(widget.serverEntry.alias, widget.roomId),
              );
            }
          },
        ),
        title: const Text('Room Information'),
        titleTextStyle: SoliplexTheme.appBarTitleStyle(context),
        actions: const [ThemeToggleButton()],
      ),
      body: FutureBuilder<Room>(
        future: _roomFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Failed to load room'));
          }
          if (!snapshot.hasData) {
            return const Center(child: Text('Room not found'));
          }
          return _RoomInfoBody(
            room: snapshot.data!,
            serverUrl: widget.serverEntry.serverUrl,
            serverEntry: widget.serverEntry,
            api: widget.serverEntry.connection.api,
            serverAlias: widget.serverEntry.alias,
            roomId: widget.roomId,
            documentsFuture: _documentsFuture,
            clientToolsFuture: _clientToolsFuture,
            onRetryDocuments: _retryDocuments,
            uploadRegistry: widget.uploadRegistry,
          );
        },
      ),
    );
  }
}

class _RoomInfoBody extends StatelessWidget {
  const _RoomInfoBody({
    required this.room,
    required this.serverUrl,
    required this.serverEntry,
    required this.api,
    required this.serverAlias,
    required this.roomId,
    required this.documentsFuture,
    required this.clientToolsFuture,
    required this.onRetryDocuments,
    required this.uploadRegistry,
  });

  final Room room;
  final Uri serverUrl;
  final ServerEntry serverEntry;
  final SoliplexApi api;
  final String serverAlias;
  final String roomId;
  final Future<List<RagDocument>> documentsFuture;
  final Future<List<Tool>> clientToolsFuture;
  final VoidCallback onRetryDocuments;
  final UploadTrackerRegistry uploadRegistry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Server',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: SoliplexSpacing.s1),
                Text(
                  formatServerUrl(serverUrl),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Room',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: SoliplexSpacing.s1),
                Text(
                  room.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          if (room.hasDescription)
            Padding(
              padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
              child: Text(
                room.description,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            ),
          _AgentCard(agent: room.agent),
          FeaturesCard(room: room, api: api, roomId: roomId),
          QuizzesCard(
            quizzes: room.quizzes,
            onQuizTapped: (quizId) => context.go(
              AppRoutes.quiz(
                serverAlias,
                roomId,
                quizId,
                from: AppRoutes.roomInfo(serverAlias, roomId),
              ),
            ),
          ),
          ExpandableListCard<MapEntry<String, RoomSkill>>(
            key: const ValueKey('skills'),
            title: 'SKILLS',
            items: room.skills.entries.toList(),
            nameOf: (e) => e.key,
            contentOf: (e) => buildSkillContent(e.value),
          ),
          ExpandableListCard<MapEntry<String, RoomTool>>(
            key: const ValueKey('tools'),
            title: 'TOOLS',
            items: room.tools.entries.toList(),
            nameOf: (e) => e.key,
            contentOf: (e) => _buildToolContent(e.value),
          ),
          ExpandableListCard<MapEntry<String, McpClientToolset>>(
            key: const ValueKey('mcp-toolsets'),
            title: 'MCP CLIENT TOOLSETS',
            emptyLabel: 'MCP client toolsets',
            items: room.mcpClientToolsets.entries.toList(),
            nameOf: (e) => e.key,
            contentOf: (e) => _buildToolsetContent(e.value),
          ),
          ClientToolsCard(clientToolsFuture: clientToolsFuture),
          if (room.enableAttachments)
            _UploadedFilesCard(
              uploadRegistry: uploadRegistry,
              serverEntry: serverEntry,
              roomId: roomId,
            ),
          DocumentsCard(
            documentsFuture: documentsFuture,
            onRetry: onRetryDocuments,
          ),
        ],
      ),
    );
  }
}

Widget _buildToolContent(RoomTool tool) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InfoRow(label: 'Kind', value: tool.kind),
      if (tool.description.isNotEmpty)
        InfoRow(label: 'Description', value: tool.description),
      if (tool.allowMcp) const InfoRow(label: 'Allow MCP', value: 'Yes'),
      if (tool.toolRequires.isNotEmpty)
        InfoRow(label: 'Requires', value: tool.toolRequires),
      if (tool.aguiFeatureNames.isNotEmpty)
        InfoRow(
          label: 'AG-UI Features',
          value: tool.aguiFeatureNames.join(', '),
        ),
    ],
  );
}

Widget _buildToolsetContent(McpClientToolset toolset) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InfoRow(label: 'Kind', value: toolset.kind),
      if (toolset.allowedTools != null)
        InfoRow(
          label: 'Allowed Tools',
          value: toolset.allowedTools!.join(', '),
        ),
    ],
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent});
  final RoomAgent? agent;

  @override
  Widget build(BuildContext context) {
    final agent = this.agent;
    if (agent == null) {
      return const SectionCard(
        title: 'AGENT',
        children: [EmptyMessage(label: 'agent')],
      );
    }
    return SectionCard(
      title: 'AGENT',
      children: [
        InfoRow(label: 'Model', value: agent.displayModelName),
        ...switch (agent) {
          DefaultRoomAgent(
            :final providerType,
            :final retries,
            :final systemPrompt,
          ) =>
            [
              InfoRow(label: 'Provider', value: providerType),
              InfoRow(label: 'Retries', value: '$retries'),
              if (systemPrompt != null)
                SystemPromptViewer(prompt: systemPrompt),
            ],
          FactoryRoomAgent(:final extraConfig) when extraConfig.isNotEmpty => [
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Extra Config',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                    const SizedBox(height: SoliplexSpacing.s1),
                    formatDynamicValue(
                      context,
                      extraConfig,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          _ => <Widget>[],
        },
        if (agent.aguiFeatureNames.isNotEmpty)
          InfoRow(
            label: 'AG-UI Features',
            value: agent.aguiFeatureNames.join(', '),
          ),
      ],
    );
  }
}

class _UploadedFilesCard extends StatefulWidget {
  const _UploadedFilesCard({
    required this.uploadRegistry,
    required this.serverEntry,
    required this.roomId,
  });

  final UploadTrackerRegistry uploadRegistry;
  final ServerEntry serverEntry;
  final String roomId;

  @override
  State<_UploadedFilesCard> createState() => _UploadedFilesCardState();
}

class _UploadedFilesCardState extends State<_UploadedFilesCard> {
  late final UploadTracker _tracker;

  @override
  void initState() {
    super.initState();
    _tracker = widget.uploadRegistry.trackerFor(
      entry: widget.serverEntry,
      roomId: widget.roomId,
    );
    // Refresh only if no other screen has populated the shared tracker
    // yet. When `RoomState` is already mounted it has refreshed on room
    // entry, so navigating Room → Info skips a redundant GET.
    if (_tracker.roomUploads(widget.roomId).value is UploadsLoading) {
      unawaited(_tracker.refreshRoom(widget.roomId));
    }
  }

  // Not disposed here — the registry owns the tracker's lifecycle.

  Future<void> _pickAndUpload() async {
    final PickedFile? file;
    try {
      file = await pickFile();
    } on PickFileException catch (e, st) {
      if (!mounted) return;
      dev.log(
        'File pick failed',
        error: e.cause,
        stackTrace: st,
        name: 'RoomInfoScreen',
        level: 1000,
      );
      final (filename, message) = switch (e) {
        PickFileReadException(:final filename) => (
            filename,
            'Failed to read file',
          ),
        PickFilePickerException(:final filename) => (
            filename ?? '(unknown)',
            'Could not open file picker',
          ),
      };
      _tracker.recordClientError(
        roomId: widget.roomId,
        filename: filename,
        message: message,
      );
      return;
    }
    if (file == null || !mounted) return;
    _tracker.uploadToRoom(
      roomId: widget.roomId,
      filename: file.name,
      fileBytes: file.bytes,
      mimeType: file.mimeType,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = _tracker.roomUploads(widget.roomId).watch(context);
    final uploads = status is UploadsLoaded ? status.uploads : null;
    final persistedCount = uploads?.whereType<PersistedUpload>().length ?? 0;
    final title = persistedCount > 0
        ? 'UPLOADED FILES ($persistedCount)'
        : 'UPLOADED FILES';

    return SectionCard(
      title: title,
      children: [
        _buildBody(status, theme),
        const SizedBox(height: SoliplexSpacing.s2),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _pickAndUpload,
            icon: const Icon(Icons.upload_file, size: 18),
            label: const Text('Upload file to room'),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(UploadsStatus status, ThemeData theme) {
    return switch (status) {
      UploadsLoading() => const Padding(
          padding: EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
          child: SizedBox(
            width: SoliplexSpacing.s4,
            height: SoliplexSpacing.s4,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      UploadsLoaded(uploads: final list) when list.isEmpty =>
        const EmptyMessage(label: 'uploaded files'),
      UploadsLoaded(uploads: final list) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: SoliplexSpacing.s2),
            for (final entry in list)
              _UploadEntryRow(entry: entry, onDismiss: _tracker.dismissFailed),
          ],
        ),
      UploadsFailed(error: final error) => Padding(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
          child: Text(
            'Failed to load uploaded files: ${uploadErrorMessage(error)}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
    };
  }
}

class _UploadEntryRow extends StatelessWidget {
  const _UploadEntryRow({
    required this.entry,
    required this.onDismiss,
  });

  final DisplayUpload entry;
  final void Function(String entryId) onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = entry is FailedUpload;
    final (icon, color, errorMessage, dismissId) = switch (entry) {
      PersistedUpload() => (
          Icons.check_circle_outline,
          theme.colorScheme.primary,
          null,
          null,
        ),
      PendingUpload() => (null, theme.colorScheme.primary, null, null),
      FailedUpload(id: final id, message: final m) => (
          Icons.error_outline,
          theme.colorScheme.onErrorContainer,
          m,
          id,
        ),
    };

    return Container(
      margin: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
      padding: isFailed
          ? const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s2, vertical: SoliplexSpacing.s1)
          : null,
      decoration: isFailed
          ? BoxDecoration(
              color: theme.colorScheme.errorContainer,
            )
          : null,
      child: Row(
        children: [
          if (icon != null)
            Icon(icon, size: 16, color: color)
          else
            const SizedBox(
              width: SoliplexSpacing.s4,
              height: SoliplexSpacing.s4,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              entry.filename,
              style: theme.textTheme.bodySmall?.copyWith(
                color: isFailed ? theme.colorScheme.onErrorContainer : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (errorMessage != null)
            Expanded(
              child: Text(
                errorMessage,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          if (dismissId != null)
            IconButton(
              icon: const Icon(Icons.close, size: 14),
              color: theme.colorScheme.onErrorContainer,
              onPressed: () => onDismiss(dismissId),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }
}
