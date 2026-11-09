import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../room_info_widgets.dart';
import 'add_people_dialog.dart';
import 'members_list.dart';
import 'members_widgets.dart';
import 'role_visuals.dart';
import 'room_access.dart';

final Logger _logger = LogManager.instance.getLogger('soliplex.room_members');

/// Who can open this room, for a server administrator.
///
/// Absent for everyone else, as the lobby's Labels tab is: the endpoints
/// refuse them, and asking would write a denied record to the audit log each
/// time they opened Room info.
class MembersCard extends StatefulWidget {
  const MembersCard({
    required this.api,
    required this.roomId,
    required this.isAdmin,
    required this.viewerClaims,
    super.key,
  });

  final SoliplexApi api;
  final String roomId;

  /// Whether the signed-in user administers the server; `null` when that
  /// could not be answered, which hides the card.
  final Future<bool?> Function() isAdmin;

  /// The signed-in user's claims, which mark their own row so the card never
  /// changes it.
  final Map<String, dynamic>? Function() viewerClaims;

  @override
  State<MembersCard> createState() => _MembersCardState();
}

class _MembersCardState extends State<MembersCard> {
  late final Future<bool?> _isAdmin = widget.isAdmin();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool?>(
      future: _isAdmin,
      builder: (context, snapshot) => snapshot.data == true
          ? _MembersCardBody(
              api: widget.api,
              roomId: widget.roomId,
              viewerClaims: widget.viewerClaims,
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Why the policy could not be shown.
enum _Failure {
  /// Usually a stored rule naming a check the server no longer has: the API
  /// answers 500 with no detail.
  serverError,

  /// The policy holds something this app cannot read, so a save would drop it.
  unreadable,

  /// The server refused, though it said the user administers it.
  forbidden,

  /// The server has no such endpoint or room.
  missing,

  /// Anything else: the network, the session.
  other,
}

sealed class _Load {
  const _Load();
}

final class _NotLoaded extends _Load {
  const _NotLoaded();
}

final class _Loading extends _Load {
  const _Loading();
}

final class _Failed extends _Load {
  const _Failed(this.failure);

  final _Failure failure;
}

final class _Loaded extends _Load {
  const _Loaded(this.policy);

  /// Null is the wire's answer for a room with no policy, which is public.
  final RoomPolicy? policy;
}

class _MembersCardBody extends StatefulWidget {
  const _MembersCardBody({
    required this.api,
    required this.roomId,
    required this.viewerClaims,
  });

  final SoliplexApi api;
  final String roomId;
  final Map<String, dynamic>? Function() viewerClaims;

  @override
  State<_MembersCardBody> createState() => _MembersCardBodyState();
}

class _MembersCardBodyState extends State<_MembersCardBody> {
  final _cancelToken = CancelToken();
  bool _expanded = false;
  _Load _load = const _NotLoaded();
  bool _saving = false;

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  // Each read writes audit records, so nothing is asked until someone opens
  // the card.
  Future<void> _fetch() async {
    setState(() => _load = const _Loading());
    try {
      final policy = await _read();
      if (mounted) setState(() => _load = _Loaded(policy));
    } on _ReadFailed catch (e) {
      if (mounted) setState(() => _load = _Failed(e.failure));
    }
  }

  Future<RoomPolicy?> _read() async {
    try {
      return await widget.api.getRoomPolicy(
        widget.roomId,
        cancelToken: _cancelToken,
      );
    } on CancelledException {
      rethrow;
    } on SoliplexException catch (e, stackTrace) {
      final failure = switch (e) {
        ApiException(statusCode: 500) => _Failure.serverError,
        MalformedResponseException() => _Failure.unreadable,
        PermissionDeniedException() => _Failure.forbidden,
        NotFoundException() => _Failure.missing,
        _ => _Failure.other,
      };
      // describeFailure, not error: a malformed body's source window would
      // carry members' addresses into the exportable log.
      _logger.warning(
        'Room policy read failed',
        attributes: {
          'roomId': widget.roomId,
          'failure': describeFailure(e),
          'kind': failure.name,
        },
        stackTrace: stackTrace,
      );
      throw _ReadFailed(failure);
    }
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded && _load is _NotLoaded) _fetch();
  }

  /// Reads again just before writing, because a save replaces the whole
  /// policy with no version check. That narrows the window for overwriting
  /// another administrator's edit; only the API could close it.
  Future<void> _write(
    RoomPolicy Function(RoomPolicy fresh) edit,
    String done,
  ) async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    try {
      final fresh = await _read();
      if (fresh == null) {
        if (mounted) setState(() => _load = const _Loaded(null));
        say('This room became public in the meantime. Nothing was changed.');
        return;
      }
      final next = edit(fresh);
      await widget.api.setRoomPolicy(next, cancelToken: _cancelToken);
      if (mounted) setState(() => _load = _Loaded(next));
      say(done);
    } on CancelledException {
      return;
    } on _ReadFailed catch (e) {
      if (mounted) setState(() => _load = _Failed(e.failure));
      say("Couldn't read this room's access, so nothing was changed.");
    } on SoliplexException catch (e, stackTrace) {
      _logger.warning(
        'Room policy save failed',
        attributes: {'roomId': widget.roomId, 'failure': describeFailure(e)},
        stackTrace: stackTrace,
      );
      say(
        e is ApiException && e.statusCode == 422
            ? 'The server refused this change. Nothing was changed.'
            : "Couldn't save. Nothing was changed.",
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _changeRole(MemberRow row, RoomRole role) async {
    if (role == row.role) return;
    final name = displayName(row.subject);
    if (row.role == RoomRole.admin &&
        !await _confirm(
          title: 'Make $name a ${role.label}?',
          body: 'They lose the room admin permission. Only the server can '
              'give it back.',
          action: 'Change role',
          icon: Icons.remove_moderator_outlined,
          danger: true,
          change: (RoomRole.admin, role),
        )) {
      return;
    }
    await _write(
      (p) => p.setRole(row.subject, role),
      '$name is now ${role.label}.',
    );
  }

  Future<void> _remove(MemberRow row, RoomPolicy policy) async {
    final name = displayName(row.subject);
    final stillOpen = policy.defaultEffect == AccessEffect.allow;
    final confirmed = await _confirm(
      title: row.isRule ? 'Remove the rule $name?' : 'Remove $name?',
      body: stillOpen
          ? 'Anyone signed in can still read this room. They only lose what '
              'this entry added.'
          : row.isRule
              ? 'Anyone who reaches this room only through this rule can no '
                  'longer open it.'
              : 'They can no longer open this room, unless a login rule still '
                  'lets them in.',
      action: row.removeLabel,
      icon: row.removeIcon,
      danger: true,
    );
    if (!confirmed) return;
    await _write((p) => p.remove(row.subject), 'Removed $name.');
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    required IconData icon,
    required bool danger,
    (RoomRole, RoomRole)? change,
  }) async {
    final answer = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (change case (final from, final to)) ...[
                Row(
                  children: [
                    RoleBadge(from),
                    const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: SoliplexSpacing.s2,
                      ),
                      child: Icon(Icons.arrow_forward, size: 16),
                    ),
                    RoleBadge(to),
                  ],
                ),
                const SizedBox(height: SoliplexSpacing.s3),
              ],
              Text(body),
            ],
          ),
        ),
        actions: [
          SoliplexButton.text(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          SoliplexButton.filled(
            onPressed: () => Navigator.pop(context, true),
            intent: danger ? ButtonIntent.danger : ButtonIntent.primary,
            icon: Icon(icon, size: 18),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer ?? false;
  }

  Future<void> _add(RoomPolicy policy) async {
    final request = await showAddPeopleDialog(context, policy: policy);
    if (request == null) return;
    final (:people, :role) = request;
    await _write(
      // Skips anyone listed since the dialog opened.
      (p) => p.add(people.where((s) => !p.lists(s)), role),
      people.length == 1
          ? 'Added ${people.single.value} as ${role.label}.'
          : 'Added ${people.length} people as ${role.label}.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow =
        MediaQuery.sizeOf(context).width < SoliplexBreakpoints.tablet;
    final load = _load;
    final count = switch (load) {
      _Loaded(:final policy?) => policy.rows.length,
      _ => null,
    };
    // SectionCard's shape, with a header that folds it. SectionCard itself
    // does not fold.
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s3),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(SoliplexSpacing.s4),
                child: Row(
                  children: [
                    Expanded(
                      child: SectionTitle(
                          count == null ? 'MEMBERS' : 'MEMBERS ($count)'),
                    ),
                    Tooltip(
                      message: 'Only server administrators see this card',
                      child: narrow
                          ? Icon(
                              Icons.shield_outlined,
                              size: 18,
                              color: theme.colorScheme.onSurfaceVariant,
                            )
                          : const SoliplexBadge(
                              label: Text('Server admins'),
                              icon: Icon(Icons.shield_outlined),
                            ),
                    ),
                    const SizedBox(width: SoliplexSpacing.s2),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (_saving) const LinearProgressIndicator(minHeight: 2),
            if (_expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SoliplexSpacing.s4,
                  0,
                  SoliplexSpacing.s4,
                  SoliplexSpacing.s4,
                ),
                child: switch (load) {
                  _NotLoaded() || _Loading() => const Padding(
                      padding: EdgeInsets.all(SoliplexSpacing.s4),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  _Failed(:final failure) => _FailedBody(
                      failure: failure,
                      roomId: widget.roomId,
                      onRetry: _fetch,
                    ),
                  _Loaded(policy: null) => _PublicBody(roomId: widget.roomId),
                  _Loaded(:final policy?) => IgnorePointer(
                      ignoring: _saving,
                      child: MembersList(
                        policy: policy,
                        viewerClaims: widget.viewerClaims(),
                        onAdd: () => _add(policy),
                        onChangeRole: _changeRole,
                        onRemove: (row) => _remove(row, policy),
                      ),
                    ),
                },
              ),
          ],
        ),
      ),
    );
  }
}

final class _ReadFailed implements Exception {
  const _ReadFailed(this.failure);

  final _Failure failure;
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({
    required this.failure,
    required this.roomId,
    required this.onRetry,
  });

  final _Failure failure;
  final String roomId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = switch (failure) {
      _Failure.serverError => (
          "The server couldn't read this room's access",
          'This usually means a login rule names a check the server no '
              "longer has. It can't be repaired here. The first command "
              'lists every entry; copy the stale rule and its permission '
              'into the second. Use --deny in place of --allow if the entry '
              'is a deny.',
        ),
      _Failure.unreadable => (
          "This room's access holds entries this app can't read",
          'Editing it here could drop them, so it is left alone. This '
              'command shows them:',
        ),
      _Failure.forbidden => (
          "The server didn't let you read this room's access",
          'Only server administrators can. Try again after signing in '
              'again.',
        ),
      _Failure.missing => (
          "This server can't show room access",
          'It may be running a version without it.',
        ),
      _Failure.other => (
          "Couldn't read this room's access",
          'Check your connection and try again.',
        ),
    };
    final commands = switch (failure) {
      _Failure.serverError => [
          showPolicyCommand(roomId),
          deleteStaleRuleCommand(roomId),
        ],
      _Failure.unreadable => [showPolicyCommand(roomId)],
      _ => const <String>[],
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AccessNotice(
          tone: NoticeTone.error,
          title: title,
          text: detail,
        ),
        for (final command in commands) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          ServerCommand(command),
        ],
        const SizedBox(height: SoliplexSpacing.s2),
        SoliplexButton.outlined(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh, size: 18),
          child: const Text('Try again'),
        ),
      ],
    );
  }
}

/// A room with no policy. Read-only, because the first save would have to
/// pick a default: left alone that default is deny, and adding one person
/// would lock everyone else out.
class _PublicBody extends StatelessWidget {
  const _PublicBody({required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const StateBadge(
          label: 'Public',
          icon: Icons.public,
          intent: BadgeIntent.warning,
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        const AccessNotice(
          icon: Icons.public,
          text: 'Everyone can open this room, and nobody has been added to '
              'it. Making it private happens on the server. People can be '
              'managed here after that.',
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        ServerCommand(makePrivateCommand(roomId)),
      ],
    );
  }
}
