import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../../shared/copy_button.dart';
import 'add_people_dialog.dart';
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
      action: row.isRule ? 'Remove rule' : 'Remove',
      icon: row.isRule ? Icons.playlist_remove : Icons.person_remove_outlined,
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
                      child: Text(
                        count == null ? 'MEMBERS' : 'MEMBERS ($count)',
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
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
                      child: _PolicyBody(
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
    final scheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme;
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
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(SoliplexSpacing.s3),
          decoration: BoxDecoration(
            color: scheme.errorContainer,
            borderRadius: BorderRadius.circular(context.radii.md),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: style.titleSmall
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
                    const SizedBox(height: SoliplexSpacing.s1),
                    Text(
                      detail,
                      style: style.bodySmall
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        for (final command in commands) ...[
          const SizedBox(height: SoliplexSpacing.s2),
          _ServerCommand(command),
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
        const _StateBadge(
          label: 'Public',
          icon: Icons.public,
          intent: BadgeIntent.warning,
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        const _Notice(
          icon: Icons.public,
          text: 'Everyone can open this room, and nobody has been added to '
              'it. Making it private happens on the server. People can be '
              'managed here after that.',
        ),
        const SizedBox(height: SoliplexSpacing.s2),
        _ServerCommand(makePrivateCommand(roomId)),
      ],
    );
  }
}

/// A warning on a tinted surface, in the card's flow.
class _Notice extends StatelessWidget {
  const _Notice({required this.text, this.icon = Icons.warning_amber});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = SoliplexTheme.of(context).colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(SoliplexSpacing.s3),
      decoration: BoxDecoration(
        color: colors.warningContainer,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: colors.onWarningContainer),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: colors.onWarningContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one way forward when the card can't act: the command, ready to copy.
class _ServerCommand extends StatelessWidget {
  const _ServerCommand(this.command);

  final String command;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s3,
        SoliplexSpacing.s1,
        SoliplexSpacing.s1,
        SoliplexSpacing.s1,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(context.radii.md),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              command,
              style: context.monospaceOn(theme.textTheme.bodySmall),
            ),
          ),
          CopyButton(text: command, tooltip: 'Copy command', iconSize: 18),
        ],
      ),
    );
  }
}

/// The room's state, always in the same colours: green while it is as closed
/// as a policy makes it, warning once anyone can read it.
class _StateBadge extends StatelessWidget {
  const _StateBadge({
    required this.label,
    required this.icon,
    required this.intent,
  });

  final String label;
  final IconData icon;
  final BadgeIntent intent;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Changed on the server, with room-authz',
        child: SoliplexBadge(
          label: Text(label),
          icon: Icon(icon),
          intent: intent,
        ),
      );
}

enum _Filter {
  all('All'),
  admin('Admin'),
  member('Member'),
  reader('Reader'),
  rules('Login rules');

  const _Filter(this.label);

  final String label;

  IconData? get icon => switch (this) {
        _Filter.all => null,
        _Filter.admin => RoomRole.admin.icon,
        _Filter.member => RoomRole.member.icon,
        _Filter.reader => RoomRole.reader.icon,
        _Filter.rules => Icons.rule,
      };

  bool matches(MemberRow row) => switch (this) {
        _Filter.all => true,
        _Filter.admin => row.role == RoomRole.admin,
        _Filter.member => row.role == RoomRole.member,
        _Filter.reader => row.role == RoomRole.reader,
        _Filter.rules => row.group == RowGroup.rules,
      };
}

class _PolicyBody extends StatefulWidget {
  const _PolicyBody({
    required this.policy,
    required this.viewerClaims,
    required this.onAdd,
    required this.onChangeRole,
    required this.onRemove,
  });

  final RoomPolicy policy;
  final Map<String, dynamic>? viewerClaims;
  final VoidCallback onAdd;
  final void Function(MemberRow row, RoomRole role) onChangeRole;
  final ValueChanged<MemberRow> onRemove;

  @override
  State<_PolicyBody> createState() => _PolicyBodyState();
}

class _PolicyBodyState extends State<_PolicyBody> {
  /// Past this, a list earns the search and chips the threads list has.
  static const _searchFrom = 9;

  /// The rows a long list shows until asked for the rest.
  static const _pageSize = 25;

  final _searchController = TextEditingController();
  String _search = '';
  _Filter _filter = _Filter.all;
  bool _showAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = widget.policy;
    final rows = policy.rows;
    final searchable = rows.length >= _searchFrom;
    final visible = rows
        .where(_filter.matches)
        .where(
          (r) =>
              _search.isEmpty ||
              displayName(r.subject).toLowerCase().contains(_search),
        )
        .toList();
    final truncated = !_showAll && visible.length > _pageSize;
    final shown = truncated ? visible.take(_pageSize).toList() : visible;
    final hasDeny = rows.any((r) => r.hasDeny);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    Widget section(RowGroup group, String title, String? help) {
      final inGroup = shown.where((r) => r.group == group).toList();
      if (inGroup.isEmpty) return const SizedBox.shrink();
      final total = visible.where((r) => r.group == group).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: SoliplexSpacing.s4,
              bottom: SoliplexSpacing.s1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title),
                      TextSpan(text: '  $total', style: muted),
                    ],
                  ),
                  style: theme.textTheme.titleSmall,
                ),
                if (help != null) Text(help, style: muted),
              ],
            ),
          ),
          for (final row in inGroup)
            _MemberTile(
              key: ValueKey(row.subject),
              row: row,
              isYou: row.isViewer(widget.viewerClaims),
              onChangeRole: (role) => widget.onChangeRole(row, role),
              onRemove: () => widget.onRemove(row),
            ),
        ],
      );
    }

    // Reachable only by removing the last entry from here, by someone who
    // reached the room through it: with nobody listed, nobody can open it.
    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Posture(policy: policy),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'Nobody is listed, so nobody can open this room.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Align(child: _AddButton(onPressed: widget.onAdd)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Beside the room's state when there is room for both, as the
            // primary action of everything below it.
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Posture(policy: policy),
                  const SizedBox(height: SoliplexSpacing.s3),
                  _AddButton(onPressed: widget.onAdd),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: _Posture(policy: policy)),
                const SizedBox(width: SoliplexSpacing.s3),
                _AddButton(onPressed: widget.onAdd),
              ],
            );
          },
        ),
        if (policy.defaultEffect == AccessEffect.allow) ...[
          const SizedBox(height: SoliplexSpacing.s3),
          const _Notice(
            icon: Icons.lock_open_outlined,
            text: 'Anyone signed in can read this room. The entries below only '
                'add more than that, so removing someone does not stop them '
                'reading.',
          ),
        ],
        if (hasDeny) ...[
          const SizedBox(height: SoliplexSpacing.s3),
          const _Notice(
            text: 'This room has deny entries. The server stops at the first '
                'entry that matches, so a deny can outrank a person listed '
                'here. This list does not show that order.',
          ),
        ],
        if (searchable) ...[
          const SizedBox(height: SoliplexSpacing.s3),
          SoliplexInput(
            controller: _searchController,
            hintText: 'Search people and rules',
            leadingIcon: const Icon(Icons.search),
            onChanged: (v) => setState(() {
              _search = v.trim().toLowerCase();
            }),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Wrap(
            spacing: SoliplexSpacing.s2,
            runSpacing: SoliplexSpacing.s1,
            children: [
              for (final filter in _Filter.values)
                SoliplexChip.filter(
                  label: Text(
                    '${filter.label} ${rows.where(filter.matches).length}',
                  ),
                  icon: filter.icon == null ? null : Icon(filter.icon),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ],
        section(RowGroup.people, 'People', null),
        section(
          RowGroup.rules,
          'Login rules',
          'Everyone whose login passes the check',
        ),
        section(
          RowGroup.other,
          'Set outside this card',
          'Shown as stored and kept when others change',
        ),
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
            child: SoliplexButton.outlined(
              onPressed: () => setState(() => _showAll = true),
              icon: const Icon(Icons.unfold_more, size: 18),
              child: Text('Show all ${visible.length}'),
            ),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: SoliplexSpacing.s4),
            child: Column(
              children: [
                Text(
                  'Nobody matches this search.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                SoliplexButton.text(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _search = '';
                      _filter = _Filter.all;
                    });
                  },
                  child: const Text('Clear search and filters'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The card's primary action, the same control wherever it appears.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SoliplexButton.filled(
        onPressed: onPressed,
        icon: const Icon(Icons.person_add_alt_outlined, size: 18),
        child: const Text('Add people'),
      );
}

/// The room's default, always in view. It cannot be changed here, which is
/// what makes changing it hard.
class _Posture extends StatelessWidget {
  const _Posture({required this.policy});

  final RoomPolicy policy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = policy.defaultEffect == AccessEffect.allow;
    return Wrap(
      spacing: SoliplexSpacing.s2,
      runSpacing: SoliplexSpacing.s1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _StateBadge(
          label: open ? 'Open to read' : 'Private',
          icon: open ? Icons.lock_open_outlined : Icons.lock_outline,
          intent: open ? BadgeIntent.warning : BadgeIntent.success,
        ),
        if (!open)
          Text(
            'Only the people and rules below can open this room.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.row,
    required this.isYou,
    required this.onChangeRole,
    required this.onRemove,
    super.key,
  });

  final MemberRow row;
  final bool isYou;
  final ValueChanged<RoomRole> onChangeRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = row.subject;
    final isRule = row.isRule;
    final mono = isRule ||
        subject.kind == AccessSubjectKind.jsonPath ||
        subject.kind == AccessSubjectKind.preferredUsername;
    final subtitle = switch (subject.kind) {
      AccessSubjectKind.preferredUsername => 'Login username',
      AccessSubjectKind.jsonPath =>
        isRule ? 'Checked at sign-in' : 'Custom rule on login claims',
      AccessSubjectKind.authenticated => 'Any signed-in user',
      AccessSubjectKind.everyone => 'Anyone at all',
      AccessSubjectKind.email => null,
    };
    const youBadge = SoliplexBadge(
      label: Text('You'),
      icon: Icon(Icons.person_outline),
    );
    Widget name({required bool withYou}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayName(subject),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono
                    ? context.monospaceOn(theme.textTheme.bodyMedium)
                    : theme.textTheme.bodyMedium,
              ),
            ),
            if (isYou && withYou) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              youBadge,
            ],
          ],
        );
    Widget detail({required bool withYou}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            name(withYou: withYou),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        );
    Widget actions({required bool aligned}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A long entry such as "Denied read, Allowed write" shrinks rather
            // than overflows a narrow row: neither pill can wrap.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _access(context),
              ),
            ),
            if (isYou && !aligned) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              youBadge,
            ],
            if (row.editable && !isYou)
              IconButton(
                icon: Icon(
                  isRule ? Icons.playlist_remove : Icons.person_remove_outlined,
                ),
                tooltip: isRule ? 'Remove rule' : 'Remove',
                onPressed: onRemove,
                // Quiet at rest, because there is one on every row; the
                // destructive colour arrives as the pointer does.
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused)
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (aligned)
              // Keeps the role chips in one column down the list.
              const SizedBox(width: 48, height: 48),
          ],
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Too narrow to hold an address beside its controls, and an address
        // is the thing that must stay readable.
        if (constraints.maxWidth < 420) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
            child: Row(
              children: [
                _Avatar(subject: subject, denied: row.hasDeny),
                const SizedBox(width: SoliplexSpacing.s3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      detail(withYou: false),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: actions(aligned: false),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
          child: Row(
            children: [
              _Avatar(subject: subject, denied: row.hasDeny),
              const SizedBox(width: SoliplexSpacing.s3),
              Expanded(child: detail(withYou: true)),
              const SizedBox(width: SoliplexSpacing.s2),
              actions(aligned: true),
            ],
          ),
        );
      },
    );
  }

  Widget _access(BuildContext context) {
    final role = row.role;
    if (isYou && role != null) {
      return Tooltip(
        message: 'Ask another administrator to change your own access',
        child: SoliplexChip(
          label: Text(role.label),
          icon: const Icon(Icons.lock_outline),
          intent: role.chipIntent,
        ),
      );
    }
    if (row.editable) {
      return _RoleMenu(current: role!, onSelected: onChangeRole);
    }
    const message = 'Shown as stored, and kept when others are edited. '
        'Change it on the server, with room-authz.';
    if (role != null) {
      return Tooltip(message: message, child: RoleBadge(role));
    }
    // Not a role: a deny is the one that takes access away, and anything else
    // is unusual enough to be worth a second look.
    return Tooltip(
      message: message,
      child: SoliplexBadge(
        label: Text(row.rawSummary),
        icon: Icon(row.hasDeny ? Icons.block : Icons.help_outline),
        intent: row.hasDeny ? BadgeIntent.danger : BadgeIntent.warning,
      ),
    );
  }
}

/// The role chip, which opens the roles. Admin is listed only for a row that
/// already holds it, so it can be taken away but not given.
class _RoleMenu extends StatefulWidget {
  const _RoleMenu({required this.current, required this.onSelected});

  final RoomRole current;
  final ValueChanged<RoomRole> onSelected;

  @override
  State<_RoleMenu> createState() => _RoleMenuState();
}

class _RoleMenuState extends State<_RoleMenu> {
  // The same idiom as the server sidebar's menu: the chip takes the tap, and
  // opens the menu through this key.
  final _menu = GlobalKey<PopupMenuButtonState<RoomRole>>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.current;
    final roles = [
      ...RoomRole.offered,
      if (!RoomRole.offered.contains(current)) current,
    ];
    return PopupMenuButton<RoomRole>(
      key: _menu,
      tooltip: 'Change role',
      onSelected: widget.onSelected,
      itemBuilder: (context) => [
        for (final role in roles)
          PopupMenuItem(
            value: role,
            padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s3,
              vertical: SoliplexSpacing.s2,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: role == current
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RoleBadge(role),
                      const SizedBox(height: SoliplexSpacing.s1),
                      Text(
                        role.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: SoliplexChip.action(
        onPressed: () => _menu.currentState?.showButtonMenu(),
        intent: current.chipIntent,
        icon: Icon(current.icon),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current.label),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.subject, this.denied = false});

  final AccessSubject subject;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPerson = subject.kind == AccessSubjectKind.email;
    final value = subject.value ?? '';
    final initial = isPerson && !denied && value.isNotEmpty;
    return CircleAvatar(
      radius: 16,
      backgroundColor: denied
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      foregroundColor: denied
          ? theme.colorScheme.onErrorContainer
          : theme.colorScheme.onSurface,
      child: initial
          ? Text(
              value.characters.first.toUpperCase(),
              style: theme.textTheme.labelMedium,
            )
          : Icon(
              switch (subject.kind) {
                _ when denied => Icons.block,
                AccessSubjectKind.jsonPath when ruleName(subject) != null =>
                  Icons.rule,
                AccessSubjectKind.preferredUsername => Icons.badge_outlined,
                AccessSubjectKind.jsonPath => Icons.data_object,
                _ => Icons.groups_outlined,
              },
              size: 18,
            ),
    );
  }
}
