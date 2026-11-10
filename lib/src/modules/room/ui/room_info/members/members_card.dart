import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../room_info_widgets.dart';
import 'add_access_dialog.dart';
import 'members_list.dart';
import 'members_widgets.dart';
import 'role_visuals.dart';
import 'room_access.dart';

/// A confirmation's content width, which keeps its text from running wide.
const double _confirmWidth = 400;

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

  final MembersFailure failure;
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

  /// Asked once per card and kept, failure included, so the card never asks
  /// again on its own. Only the dialog's Try again replaces it.
  Future<List<LoginCheck>>? _checks;

  /// What [_checks] answered, once it succeeds, so the rule rows can show
  /// each check's description without waiting on it.
  List<LoginCheck>? _knownChecks;

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
      _show(policy);
    } on CancelledException {
      // Only dispose cancels, so there is nothing left to show it on.
      return;
    } on _ReadFailed catch (e) {
      if (mounted) setState(() => _load = _Failed(e.failure));
    }
  }

  void _show(RoomPolicy? policy) {
    if (!mounted) return;
    setState(() => _load = _Loaded(policy));
    _describeRules(policy);
  }

  Future<List<LoginCheck>> _loadChecks() => _checks ??= _fetchChecks();

  Future<List<LoginCheck>> _reloadChecks() => _checks = _fetchChecks();

  Future<List<LoginCheck>> _fetchChecks() async {
    try {
      final checks = await widget.api.getLoginChecks(cancelToken: _cancelToken);
      // Logged here, once per read, rather than in the dialog's build. Check
      // names are identifiers the server registers, not credentials.
      final unusable = [
        for (final c in checks)
          if (ruleFor(c.name) == null) c.name,
      ];
      if (unusable.isNotEmpty) {
        _logger.info(
          'Login checks a rule cannot name',
          attributes: {'names': unusable},
        );
      }
      if (mounted) setState(() => _knownChecks = checks);
      return checks;
    } on CancelledException {
      rethrow;
    } catch (e, stackTrace) {
      // As for the policy read: a SoliplexException carries no value worth
      // hiding, anything else is reduced to its shape.
      _logger.warning(
        'Login checks read failed',
        error: e is SoliplexException ? e : null,
        attributes: {
          if (e is ApiException) 'statusCode': e.statusCode,
          if (e is! SoliplexException) 'failure': describeFailure(e),
        },
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Rule rows show what their check does, so the checks are asked for as
  /// soon as a policy holding a rule is shown. A failure leaves the rows
  /// without descriptions, and is what the dialog's Login rule pane shows
  /// until Try again.
  void _describeRules(RoomPolicy? policy) {
    if (_checks != null || policy == null) return;
    if (policy.rows.any((r) => r.isRule)) _loadChecks().ignore();
  }

  Future<RoomPolicy?> _read() async {
    try {
      return await widget.api.getRoomPolicy(
        widget.roomId,
        cancelToken: _cancelToken,
      );
    } on CancelledException {
      rethrow;
    } catch (e, stackTrace) {
      // Bare, as in AdminStatus: a closed client's StateError or a refresh
      // failure must end in the failed state too, not a spinner. `error: e`
      // is safe for a SoliplexException: an ApiException carries the status
      // and the server's own reason, a NetworkException the host, and the
      // transport builds a MalformedResponseException's message without the
      // body. Anything else is free to carry a value, so only its shape is
      // kept.
      final failure = failureOf(e);
      _logger.warning(
        'Room policy read failed',
        error: e is SoliplexException ? e : null,
        attributes: {
          'roomId': widget.roomId,
          if (e is ApiException) 'statusCode': e.statusCode,
          if (e is! SoliplexException) 'failure': describeFailure(e),
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
  ///
  /// The edit is planned against that read, so a row changed in the meantime
  /// is shown as it now is rather than overwritten.
  Future<void> _write(
    MemberEdit edit,
    String Function(RoomPolicy fresh) done,
  ) async {
    // Every caller arrives here from a dialog, which the card may not have
    // outlived.
    if (!mounted) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    // Kept outside the try, so a failed save can still show what was read.
    RoomPolicy? fresh;
    try {
      fresh = await _read();
      if (fresh == null) {
        _show(null);
        say('This room became public in the meantime. Nothing was changed.');
        return;
      }
      final read = fresh;
      switch (planEdit(read, edit)) {
        case RowChanged(:final subject):
          _show(read);
          say(
            '${displayName(subject)} changed since you opened this. Check it '
            'and try again.',
          );
        case NoChange():
          _show(read);
          say('Nothing to change: the list already says so.');
        case SaveEdit(:final next):
          await widget.api.setRoomPolicy(next, cancelToken: _cancelToken);
          _show(next);
          say(done(read));
      }
    } on CancelledException {
      return;
    } on _ReadFailed catch (e) {
      if (mounted) setState(() => _load = _Failed(e.failure));
      say("Couldn't read this room's access, so nothing was changed.");
    } catch (e, stackTrace) {
      // Bare and reduced as for the read.
      _logger.warning(
        'Room policy save failed',
        error: e is SoliplexException ? e : null,
        attributes: {
          'roomId': widget.roomId,
          if (e is ApiException) 'statusCode': e.statusCode,
          if (e is! SoliplexException) 'failure': describeFailure(e),
        },
        stackTrace: stackTrace,
      );
      // The list shows the policy as last read, not as first shown: another
      // administrator's change is not hidden behind a failed save.
      if (fresh case final read?) _show(read);
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
    await _write(SetRole(row, role), (_) => '$name is now ${role.label}.');
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
    await _write(RemoveMember(row), (_) => 'Removed $name.');
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
          width: _confirmWidth,
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
    final request = await showAddAccessDialog(
      context,
      policy: policy,
      loadChecks: _loadChecks,
      reloadChecks: _reloadChecks,
    );
    if (request == null) return;
    final (:subjects, :role) = request;
    await _write(
      AddMembers(subjects, role),
      // Counts only those not listed since the dialog opened.
      (fresh) {
        final added = [
          for (final s in subjects)
            if (!fresh.lists(s)) s,
        ];
        if (added.length == 1) {
          final subject = added.single;
          return subject.kind == AccessSubjectKind.jsonPath
              ? 'Added the ${displayName(subject)} rule as ${role.label}.'
              : 'Added ${displayName(subject)} as ${role.label}.';
        }
        return 'Added ${added.length} people as ${role.label}.';
      },
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
                        checks: _knownChecks,
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

  final MembersFailure failure;
}

class _FailedBody extends StatelessWidget {
  const _FailedBody({
    required this.failure,
    required this.roomId,
    required this.onRetry,
  });

  final MembersFailure failure;
  final String roomId;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final (title, detail) = switch (failure) {
      MembersFailure.serverError => (
          "The server couldn't read this room's access",
          'This usually means a login rule names a check the server no '
              "longer has. It can't be repaired here. The first command "
              'lists every entry; copy the stale rule and its permission '
              'into the second. Use --deny in place of --allow if the entry '
              'is a deny.',
        ),
      MembersFailure.unreadable => (
          "The server's answer about this room's access couldn't be read",
          "It may hold entries this app doesn't know, or something other "
              'than the server answered. Nothing can be changed here. This '
              'command shows what is stored:',
        ),
      MembersFailure.session => (
          'Your session has expired',
          'Sign in again, then try again.',
        ),
      MembersFailure.network => (
          "Couldn't reach the server",
          'Check your connection and try again.',
        ),
      MembersFailure.forbidden => (
          "The server didn't let you read this room's access",
          'Only server administrators can. Try again after signing in '
              'again.',
        ),
      MembersFailure.missing => (
          "This server can't show room access",
          'It may be running a version without it.',
        ),
      MembersFailure.other => (
          "Couldn't read this room's access",
          'Try again.',
        ),
    };
    final commands = switch (failure) {
      MembersFailure.serverError => [
          showPolicyCommand(roomId),
          deleteStaleRuleCommand(roomId),
        ],
      MembersFailure.unreadable => [showPolicyCommand(roomId)],
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
