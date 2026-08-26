import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_client/soliplex_client.dart' hide Room, State;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../pick_file.dart';

import '../../../core/routes.dart';
import '../../auth/server_entry.dart';
import '../../auth/ui/home_shell.dart';
import '../upload_tracker.dart';
import '../upload_tracker_registry.dart';
import 'room_info/chunk_lookup_card.dart';
import 'room_info/client_tools_card.dart';
import 'room_info/documents_card.dart';
import 'room_info/expandable_list_card.dart';
import 'room_info/features_card.dart';
import 'room_info/quizzes_card.dart';
import 'room_info/room_info_widgets.dart';
import 'room_info/skill_card.dart';
import 'room_info/system_prompt_viewer.dart';
import '../../../shared/selectable_content.dart';
import 'package:soliplex_design/soliplex_design.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.room_info_screen');

class RoomInfoScreen extends StatefulWidget {
  const RoomInfoScreen({
    super.key,
    required this.serverEntry,
    required this.roomId,
    required this.toolRegistryResolver,
    required this.uploadRegistry,
    required this.appName,
    this.logo,
  });

  final ServerEntry serverEntry;
  final String roomId;
  final Future<ToolRegistry> Function(String roomId) toolRegistryResolver;
  final UploadTrackerRegistry uploadRegistry;
  final String appName;
  final Widget? logo;

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
      body: SafeArea(
        child: Column(
          children: [
            HomeShellHeader(
              appName: widget.appName,
              logo: widget.logo,
              showUtilityMenu: false,
              leading: IconButton(
                icon: Icon(Icons.adaptive.arrow_back),
                tooltip: 'Back to room',
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
            ),
            Expanded(
              child: FutureBuilder<Room>(
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
            ),
          ],
        ),
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
      child: SelectableContent(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionCard(
              title: 'SERVER',
              children: [
                Text(
                  formatServerUrl(serverUrl),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            SectionCard(
              title: 'ROOM',
              children: [
                Text(
                  room.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
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
            if (room.acceptsRoomUploads)
              _UploadedFilesCard(
                uploadRegistry: uploadRegistry,
                serverEntry: serverEntry,
                roomId: roomId,
              ),
            DocumentsCard(
              documentsFuture: documentsFuture,
              onRetry: onRetryDocuments,
            ),
            ChunkLookupCard(api: api, roomId: roomId),
          ],
        ),
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

/// What is known about whether the signed-in user may upload to this room.
///
/// Four states rather than a `bool?`, because a question that was *not
/// answered* is not the same as one answered "no", and the two must not render
/// alike: the refusal names who does add the files, which is a claim about the
/// user this client is in no position to make when it never got an answer.
enum _UploadPermission {
  /// The answer is outstanding and still within [_UploadedFilesCardState
  /// ._permissionWait].
  checking,

  /// The installation said the user is an administrator.
  permitted,

  /// The installation said the user is not one.
  refused,

  /// The question could not be answered — the request failed, or was still
  /// queued at the bound. Not a verdict, and never rendered as one.
  unknown,
}

class _UploadedFilesCardState extends State<_UploadedFilesCard> {
  late final UploadTracker _tracker;

  /// What is known about the caller's permission to upload here.
  ///
  /// The controls are offered only under [_UploadPermission.permitted]. An
  /// unanswered check withholds them and says so, because the upload `POST`
  /// authorizes through the same installation-side administrator check this
  /// answer comes from: when that check cannot answer, it cannot authorize
  /// either, so offering the controls would offer an action whose every use
  /// fails — a folder of N files uploaded in full to be refused N times.
  _UploadPermission _permission = _UploadPermission.checking;

  @override
  void initState() {
    super.initState();
    _tracker = widget.uploadRegistry.trackerFor(
      entry: widget.serverEntry,
      roomId: widget.roomId,
    );
    unawaited(_resolveUploadPermission());
    // Refresh only if no other screen has populated the shared tracker
    // yet. When `RoomState` is already mounted it has refreshed on room
    // entry, so navigating Room → Info skips a redundant GET.
    if (_tracker.roomUploads(widget.roomId).value is UploadsLoading) {
      unawaited(_tracker.refreshRoom(widget.roomId));
    }
  }

  // Not disposed here — the registry owns the tracker's lifecycle.

  /// How long the controls may stay in their loading state before the check is
  /// reported as one that has not answered.
  ///
  /// The request's own timeout does not bound this: it starts only once the
  /// request holds one of the six connection slots shared with every other
  /// request to this server, and an upload already running can hold one for
  /// the whole 600 seconds the transport allows it. Loading renders as
  /// disabled, so without a bound the controls would sit unpressable and
  /// unexplained for as long as that queue lasts. The bound does not end the
  /// request — an answer arriving later still replaces what the bound wrote.
  static const Duration _permissionWait = Duration(seconds: 3);

  /// Uploading to a room needs an administrator, which is a fact about the
  /// user rather than the room, so it arrives separately from the room itself.
  ///
  /// `AdminStatus.read` never completes with an error, so nothing here needs a
  /// guard beyond [mounted].
  ///
  /// Safe to re-enter, which is what the retry control does. A reader that has
  /// been overtaken either returns without writing — `settled == null` is the
  /// only state it could write, and it declines to — or resolves the same
  /// definite answer as the reader that overtook it, because
  /// [AdminStatus.read] hands both the same request while one is in flight.
  Future<void> _resolveUploadPermission() async {
    final answer = widget.serverEntry.adminStatus.read();
    var timedOut = false;
    final bounded = await answer.timeout(
      _permissionWait,
      onTimeout: () {
        timedOut = true;
        return null;
      },
    );
    if (!mounted) return;
    if (bounded != null) {
      _settle(bounded);
      return;
    }

    // Every arrival at [_UploadPermission.unknown] is recorded, because the
    // state is indistinguishable on screen from an installation that simply
    // has no answer to give, and because the two ways of reaching it warrant
    // different action: `queued` says the server is slow or the client's
    // connection pool is saturated, `unanswered` says the request failed and
    // `AdminStatus` has already described how. At `warning` because the
    // release log floor drops anything lower, and this is the state a user
    // reports. After the [mounted] check, so the record describes a state that
    // was actually rendered.
    //
    // A request that outruns the bound and *then* fails is recorded twice —
    // correctly: the wait and the failure are separate events, and only the
    // first is about this screen.
    _logger.warning(
      'Could not confirm whether the user administers this room; withholding '
      'the room upload controls',
      attributes: {
        'roomId': widget.roomId,
        'reason': timedOut ? 'queued' : 'unanswered',
      },
    );
    setState(() => _permission = _UploadPermission.unknown);

    // The request outlives the bound, so a definite answer of either polarity
    // still replaces what the bound wrote. A `null` leaves it alone: that is
    // either the failure this state already describes, or an answer `clear`
    // retired because it describes a different user.
    final settled = await answer;
    if (!mounted || settled == null) return;
    _settle(settled);
  }

  /// Records and applies a verdict the installation delivered.
  ///
  /// Recorded at `info`, below the release log floor, because neither outcome
  /// is a fault — but which one it was is the first question asked of a user
  /// who says the controls are missing, or present when they should not be.
  /// Without it a diagnostics export cannot tell "the server said yes" from
  /// "the gate never ran".
  void _settle(bool isAdmin) {
    _logger.info(
      'The installation answered on whether the user administers this room',
      attributes: {'roomId': widget.roomId, 'isAdmin': isAdmin},
    );
    setState(
      () => _permission =
          isAdmin ? _UploadPermission.permitted : _UploadPermission.refused,
    );
  }

  Future<void> _pickAndUpload(
    Future<PickFilesResult?> Function() pick,
  ) async {
    final PickFilesResult? result;
    try {
      result = await pick();
    } on PickFilePickerException catch (e, st) {
      if (!mounted) return;
      _logger.error(
        'Pick failed',
        error: e.cause,
        stackTrace: st,
      );
      _tracker.recordClientError(
        roomId: widget.roomId,
        filename: '(unknown)',
        message: pickerErrorMessage(e.cause),
      );
      return;
    }
    if (result == null || !mounted) return;
    // No permission recheck here. The pick outlives the tap that opened it,
    // but the controls are pressable only under [_UploadPermission.permitted],
    // which is written from a definite answer and nothing then moves it. A
    // grant revoked server-side while the picker was open is left to the
    // tracker, which renders the `PermissionDeniedException` the POST comes
    // back with.
    for (final itemError in result.errors) {
      _logger.error(
        'Pick failed',
        error: itemError.cause,
        attributes: {'filename': itemError.filename},
      );
      _tracker.recordClientError(
        roomId: widget.roomId,
        filename: itemError.filename,
        message: pickerErrorMessage(itemError.cause),
      );
    }
    for (final file in result.files) {
      _tracker.uploadToRoom(
        roomId: widget.roomId,
        filename: file.name,
        openStream: file.openStream,
        contentLength: file.size,
        mimeType: file.mimeType,
        webFileBlob: file.webFileBlob,
      );
    }
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
        // One slot, one occupant per state, so whatever the check withholds
        // leaves something in its place. Never empty: an absent control would
        // read as a refusal the client has not been told.
        const SizedBox(height: SoliplexSpacing.s2),
        switch (_permission) {
          // Present but unpressable, because a control on its way says more
          // than no control at all. [_permissionWait] bounds how long this
          // lasts.
          _UploadPermission.checking ||
          _UploadPermission.permitted =>
            _buildUploadControls(
              isLoading: _permission == _UploadPermission.checking,
            ),
          // The installation answered, so the client may say who does add
          // them. Stands whether or not the list is empty.
          _UploadPermission.refused => Text(
              'An administrator adds files to this room.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          // Says only what is true: the check did not answer. Naming an
          // administrator here would assert something about the user that
          // nothing established, to someone who may well be one.
          _UploadPermission.unknown => _buildPermissionUnknown(theme),
        },
      ],
    );
  }

  /// The two upload controls, greyed while the check is outstanding.
  Widget _buildUploadControls({required bool isLoading}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: SoliplexSpacing.s2,
        runSpacing: SoliplexSpacing.s2,
        children: [
          SoliplexButton.filled(
            onPressed: () => _pickAndUpload(pickFiles),
            isLoading: isLoading,
            icon: const Icon(Icons.upload_file, size: 18),
            child: const Text('Upload files to room'),
          ),
          SoliplexButton.filled(
            onPressed: () => _pickAndUpload(pickFolder),
            isLoading: isLoading,
            icon: const Icon(Icons.drive_folder_upload, size: 18),
            child: const Text('Upload folder to room'),
          ),
        ],
      ),
    );
  }

  /// What stands in the controls' slot when the check did not answer.
  ///
  /// Carries its own retry because the alternative recourse — leaving the
  /// screen and returning — is not discoverable from a sentence that does not
  /// mention it. A retry costs one request: an unanswered check is never kept,
  /// so [AdminStatus.read] asks again rather than replaying the non-answer.
  /// While one is still in flight it joins that request instead of issuing a
  /// second, which is why pressing this repeatedly cannot stack them up.
  Widget _buildPermissionUnknown(ThemeData theme) {
    // The failed-row shape `DocumentsCard` uses, so the two cards on this
    // screen that can fail read alike. It also carries its weight: the refusal
    // this slot otherwise holds is an ordinary state in ordinary type, and
    // rendering a failure the same way would leave "you may not add files"
    // and "nobody could find out" indistinguishable at a glance.
    return Row(
      children: [
        Icon(
          Icons.error_outline,
          size: 18,
          color: theme.colorScheme.error,
        ),
        const SizedBox(width: SoliplexSpacing.s2),
        Expanded(
          child: Text(
            "Couldn't check whether you can add files here.",
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
        SoliplexButton.filled(
          onPressed: () {
            setState(() => _permission = _UploadPermission.checking);
            unawaited(_resolveUploadPermission());
          },
          child: const Text('Retry'),
        ),
      ],
    );
  }

  Widget _buildBody(UploadsStatus status, ThemeData theme) {
    return switch (status) {
      UploadsLoading() => const Padding(
          padding: EdgeInsets.symmetric(vertical: SoliplexSpacing.s2),
          child: SizedBox(
            width: 16,
            height: 16,
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
              _UploadEntryRow(
                entry: entry,
                onCancel: _tracker.cancelUpload,
                onDismiss: _tracker.dismissFailed,
              ),
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
    required this.onCancel,
    required this.onDismiss,
  });

  final DisplayUpload entry;
  final void Function(String entryId) onCancel;
  final void Function(String entryId) onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFailed = entry is FailedUpload;
    final (icon, color, errorMessage) = switch (entry) {
      PersistedUpload() => (
          Icons.check_circle_outline,
          context.success,
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
      PendingUpload(:final id) => ('Cancel upload', () => onCancel(id)),
      FailedUpload(:final id) => ('Dismiss', () => onDismiss(id)),
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
              borderRadius: BorderRadius.circular(context.radii.sm),
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
                value: switch (entry) {
                  PendingUpload(:final progress) => progress,
                  _ => null,
                },
              ),
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
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
}
