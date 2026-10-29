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
import 'upload_entry_row.dart';
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
            _AgentCard(
              agent: room.agent,
              unreadable: room.agentUnreadable,
            ),
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
                userHasWrite: room.userHasWrite,
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
      if (tool.extraParameters.isNotEmpty)
        Builder(
          builder: (context) => DialogButton(
            label: 'Show more',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => RawParametersDialog(
                title: tool.name,
                sections: [('Extra Parameters', tool.extraParameters)],
              ),
            ),
          ),
        ),
    ],
  );
}

/// Renders an MCP toolset's kind and its allow-list.
///
/// `toolset_params` is deliberately not rendered. It is the raw,
/// uninterpolated transport config — `headers` and `query_params` for an HTTP
/// toolset, `env` for a stdio one (`config/tools.py`) — and those are named
/// places a credential goes, either literally or as the `secret:` markers
/// only the backend resolves. The interpolated copy the backend builds to
/// reach the server is a separate property it does not send.
///
/// This is not a confidentiality boundary. The room payload carrying those
/// values already reaches every user authorised for the room, so withholding
/// them reduces incidental exposure — screenshots, screen shares, a support
/// session — and nothing more. The fix that would matter is the backend not
/// serialising them. That is also why the other raw maps on this screen are
/// still rendered: a skill's and a tool's `extra_parameters` and a factory
/// agent's `extra_config` are arbitrary operator dicts with no named slot a
/// secret goes in, and hiding them would buy less than the inconsistency
/// costs.
Widget _buildToolsetContent(McpClientToolset toolset) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      InfoRow(label: 'Kind', value: toolset.kind),
      if (toolset.allowedTools.isNotEmpty)
        InfoRow(
          label: 'Allowed Tools',
          value: toolset.allowedTools.join(', '),
        ),
    ],
  );
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent, required this.unreadable});
  final RoomAgent? agent;

  /// The payload carried an agent this client could not read, so the card
  /// must not say the room has none.
  final bool unreadable;

  @override
  Widget build(BuildContext context) {
    final agent = this.agent;
    if (agent == null) {
      return SectionCard(
        title: 'AGENT',
        children: [
          EmptyMessage(
            label: unreadable ? 'readable agent configuration' : 'agent',
          ),
        ],
      );
    }
    return SectionCard(
      title: 'AGENT',
      children: [
        // The wire has no one field that names all three shapes, so each
        // labels its own headline row.
        ...switch (agent) {
          DefaultRoomAgent(
            :final modelName,
            :final providerType,
            :final retries,
            :final systemPrompt,
          ) =>
            [
              if (modelName != null && modelName.isNotEmpty)
                InfoRow(label: 'Model', value: modelName),
              if (providerType.isNotEmpty)
                InfoRow(label: 'Provider', value: providerType),
              if (retries != null) InfoRow(label: 'Retries', value: '$retries'),
              if (systemPrompt != null)
                SystemPromptViewer(prompt: systemPrompt),
            ],
          FactoryRoomAgent(:final factoryName, :final extraConfig) => [
              InfoRow(label: 'Factory', value: factoryName),
              if (extraConfig.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Extra Config',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
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
          OtherRoomAgent(:final kind) => [
              if (kind.isNotEmpty)
                InfoRow(label: 'Kind', value: kind)
              else
                const EmptyMessage(label: 'agent configuration this app reads'),
            ],
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
    required this.userHasWrite,
  });

  final UploadTrackerRegistry uploadRegistry;
  final ServerEntry serverEntry;
  final String roomId;

  /// The user's write permission for the room as the server returned it, or
  /// `null` when it was not returned, in which case the administrator check
  /// stands in.
  final bool? userHasWrite;

  @override
  State<_UploadedFilesCard> createState() => _UploadedFilesCardState();
}

/// What is known about whether the signed-in user may add files to this room
/// or delete them: one answer, because the two need the same permission.
///
/// Five states rather than a `bool?`, because a question that was *not
/// answered* is not the same as one answered "no", and the two must not render
/// alike: the refusal tells the user they cannot add files, which is a claim
/// about the user this client is in no position to make when it never got an
/// answer.
///
/// When the user's write permission is not returned, the administrator check
/// stands in. A "no" from it is [unconfirmed] rather than [refused]: a user who
/// is not an administrator may still hold the permission, so the client
/// withholds the controls without claiming they cannot add files.
enum _UploadPermission {
  /// The answer is outstanding and still within [_UploadedFilesCardState
  /// ._permissionWait].
  checking,

  /// The server returned the user's write permission as held or, when it
  /// returned none, said the user is an administrator.
  permitted,

  /// The server returned the user's write permission as not held.
  refused,

  /// The server returned no write permission and said the user is not an
  /// administrator.
  unconfirmed,

  /// The question could not be answered — the request failed, or was still
  /// queued at the bound. Not a verdict, and never rendered as one.
  unknown,
}

class _UploadedFilesCardState extends State<_UploadedFilesCard> {
  late final UploadTracker _tracker;

  /// What is known about the caller's permission to upload here.
  ///
  /// The controls are offered only under [_UploadPermission.permitted]. An
  /// unanswered check withholds them and says so, because nothing established
  /// that the user may upload, and offering the controls could offer an action
  /// whose every use fails — a folder of N files uploaded in full to be
  /// refused N times.
  _UploadPermission _permission = _UploadPermission.checking;

  @override
  void initState() {
    super.initState();
    _tracker = widget.uploadRegistry.trackerFor(
      entry: widget.serverEntry,
      roomId: widget.roomId,
    );
    switch (widget.userHasWrite) {
      case true:
        _permission = _UploadPermission.permitted;
      case false:
        _permission = _UploadPermission.refused;
      case null:
        unawaited(_resolveUploadPermission());
    }
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

  /// Stands in for the user's write permission when it is not returned: an
  /// administrator holds that permission implicitly, and being one is a fact
  /// about the user rather than the room, so it arrives separately from the
  /// room itself. A user who is not an administrator is not offered the
  /// upload or delete controls, whether or not they hold the permission.
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
      'Could not confirm whether the user is an administrator; withholding the '
      'room upload and delete controls',
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
  /// who says the upload or delete controls are missing, or present when they
  /// should not be.
  /// Without it a diagnostics export cannot tell "the administrator check said
  /// yes" from "it never ran". When the server returns the write permission
  /// this check does not run and nothing is recorded here. The client's
  /// warning that the permission was not returned, if present, says only that
  /// it was left out for at least one room.
  void _settle(bool isAdmin) {
    _logger.info(
      'The installation answered on whether the user is an administrator',
      attributes: {'roomId': widget.roomId, 'isAdmin': isAdmin},
    );
    setState(
      () => _permission =
          isAdmin ? _UploadPermission.permitted : _UploadPermission.unconfirmed,
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
          // The server returned the permission as not held, so the client may
          // say the user cannot add them. Stands whether or not the list is
          // empty, as does the note below.
          _UploadPermission.refused => _buildPermissionNote(
              "You can't add files to this room.",
              theme,
            ),
          // Says only what is true: the server did not return the permission,
          // and the administrator check cannot speak for a user who holds it.
          _UploadPermission.unconfirmed => _buildPermissionNote(
              'The server did not return whether you can write to this room.',
              theme,
            ),
          // Says only what is true: the check did not answer. A refusal here
          // would assert something about the user that nothing established, to
          // someone who may well be allowed.
          _UploadPermission.unknown => _buildPermissionUnknown(theme),
        },
      ],
    );
  }

  /// What stands in the controls' slot when they are withheld on an answer.
  Widget _buildPermissionNote(String text, ThemeData theme) {
    return Text(
      text,
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
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
    // screen that can fail read alike. It also carries its weight: the notes
    // this slot otherwise holds are ordinary states in ordinary type, and
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
              UploadEntryRow(
                entry: entry,
                onCancel: _tracker.cancelUpload,
                onDismiss: _tracker.dismissFailed,
                // The upload controls' answer: deleting a room upload needs
                // the same permission as adding one.
                onDelete: _permission == _UploadPermission.permitted
                    ? (filename) => unawaited(_tracker.deleteRoomUpload(
                          roomId: widget.roomId,
                          filename: filename,
                        ))
                    : null,
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
