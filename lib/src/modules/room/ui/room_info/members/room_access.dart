/// How the members card reads a room's access policy, and the edits it makes.
///
/// Nothing here extends the API. A role is this app's name for a set of the
/// policy's entries, and a login rule is its name for an entry whose JSONPath
/// calls one registered check.
library;

import 'package:soliplex_client/soliplex_client.dart';

/// The roles the card shows. Each is a set of independent entries, because
/// the server never lets one permission imply another.
enum RoomRole {
  reader('Reader', 'Can open the room and chat', {AccessPermission.read}),
  member(
    'Member',
    'Reader, and can add and remove room files',
    {AccessPermission.read, AccessPermission.write},
  ),

  /// Shown for entries set elsewhere, never offered: nothing on the server
  /// checks the admin permission yet.
  admin(
    'Admin',
    'Member, and holds the room admin permission',
    {AccessPermission.read, AccessPermission.write, AccessPermission.admin},
  );

  const RoomRole(this.label, this.description, this.permissions);

  final String label;
  final String description;
  final Set<AccessPermission> permissions;

  /// The roles the card grants.
  static const offered = [reader, member];

  static RoomRole? fromPermissions(Set<AccessPermission> permissions) {
    for (final role in values) {
      if (role.permissions.length == permissions.length &&
          role.permissions.containsAll(permissions)) {
        return role;
      }
    }
    return null;
  }
}

/// The JSONPath a login rule is stored as: `$[?name($)]`, one registered
/// check applied to the login's claims.
final _rulePath = RegExp(r'^\$\[\?([A-Za-z_][A-Za-z0-9_]*)\(\$\)\]$');

/// The check a JSONPath subject calls, or `null` when it is any other query.
String? ruleName(AccessSubject subject) =>
    subject.kind == AccessSubjectKind.jsonPath
        ? _rulePath.firstMatch(subject.value!)?.group(1)
        : null;

/// How a subject reads on the card.
String displayName(AccessSubject subject) => switch (subject.kind) {
      AccessSubjectKind.everyone => 'Everyone',
      AccessSubjectKind.authenticated => 'Everyone signed in',
      AccessSubjectKind.jsonPath => ruleName(subject) ?? subject.value!,
      _ => subject.value!,
    };

/// Which part of the card a row belongs in.
enum RowGroup { people, rules, other }

/// One subject's entries, shown as a single line of the card.
final class MemberRow {
  const MemberRow(this.subject, this.entries);

  final AccessSubject subject;
  final List<AccessEntry> entries;

  bool get hasDeny => entries.any((e) => e.effect == AccessEffect.deny);

  /// Null when the entries are not a role: a deny, or write without read.
  RoomRole? get role => hasDeny
      ? null
      : RoomRole.fromPermissions({for (final e in entries) e.permission});

  bool get isPerson =>
      subject.kind == AccessSubjectKind.email ||
      subject.kind == AccessSubjectKind.preferredUsername;

  bool get isRule => ruleName(subject) != null;

  /// The card edits only what it can say plainly. Everything else is shown,
  /// and written back untouched.
  bool get editable => role != null && (isPerson || isRule);

  RowGroup get group => !editable
      ? RowGroup.other
      : isPerson
          ? RowGroup.people
          : RowGroup.rules;

  /// What a row that is not a role grants, in the server's words.
  String get rawSummary => [
        for (final e in entries)
          '${e.effect == AccessEffect.deny ? 'Denied' : 'Allowed'} '
              '${e.permission.name}',
      ].join(', ');

  /// Whether this row is about the signed-in user, whose own access the card
  /// never changes.
  bool isViewer(Map<String, dynamic>? claims) {
    final claim = switch (subject.kind) {
      AccessSubjectKind.email => claims?['email'],
      AccessSubjectKind.preferredUsername => claims?['preferred_username'],
      _ => null,
    };
    // Exact, as the server compares them.
    return claim is String && claim == subject.value;
  }
}

/// The groups the list's chips narrow it to.
enum MemberFilter {
  all('All'),
  admin('Admin'),
  member('Member'),
  reader('Reader'),
  rules('Login rules');

  const MemberFilter(this.label);

  final String label;

  bool matches(MemberRow row) => switch (this) {
        MemberFilter.all => true,
        MemberFilter.admin => row.role == RoomRole.admin,
        MemberFilter.member => row.role == RoomRole.member,
        MemberFilter.reader => row.role == RoomRole.reader,
        MemberFilter.rules => row.group == RowGroup.rules,
      };
}

/// What [filter] and [search] leave of [rows] as `matching`, and the first
/// [limit] of those as `shown`; all of them when [limit] is null.
///
/// [search] matches anywhere in a row's name, ignoring case.
({List<MemberRow> matching, List<MemberRow> shown}) visibleRows(
  List<MemberRow> rows, {
  MemberFilter filter = MemberFilter.all,
  String search = '',
  int? limit,
}) {
  final needle = search.trim().toLowerCase();
  final matching = [
    for (final row in rows)
      if (filter.matches(row) &&
          (needle.isEmpty ||
              displayName(row.subject).toLowerCase().contains(needle)))
        row,
  ];
  final shown = limit == null || matching.length <= limit
      ? matching
      : matching.sublist(0, limit);
  return (matching: matching, shown: shown);
}

/// The card's reading of a policy and the edits it makes. Each edit returns a
/// whole policy, because saving replaces the stored one.
extension RoomPolicyEdits on RoomPolicy {
  /// One row per subject, in the order each subject first appears.
  List<MemberRow> get rows {
    final bySubject = <AccessSubject, List<AccessEntry>>{};
    for (final entry in entries) {
      (bySubject[entry.subject] ??= []).add(entry);
    }
    return [for (final e in bySubject.entries) MemberRow(e.key, e.value)];
  }

  bool lists(AccessSubject subject) => entries.any((e) => e.subject == subject);

  /// Appends, as the CLI does: a new grant must not jump ahead of a deny that
  /// someone placed first on purpose.
  RoomPolicy add(Iterable<AccessSubject> subjects, RoomRole role) =>
      withEntries([
        ...entries,
        for (final subject in subjects)
          for (final permission in role.permissions)
            AccessEntry(subject, permission),
      ]);

  /// Changes one subject's entries in place, so the rest of the policy keeps
  /// its order.
  RoomPolicy setRole(AccessSubject subject, RoomRole role) {
    final kept = {
      for (final e in entries)
        if (e.subject == subject && role.permissions.contains(e.permission))
          e.permission,
    };
    final next = [
      for (final e in entries)
        if (e.subject != subject || role.permissions.contains(e.permission)) e,
    ];
    final at = next.lastIndexWhere((e) => e.subject == subject) + 1;
    next.insertAll(at == 0 ? next.length : at, [
      for (final permission in role.permissions)
        if (!kept.contains(permission)) AccessEntry(subject, permission),
    ]);
    return withEntries(next);
  }

  RoomPolicy remove(AccessSubject subject) => withEntries([
        for (final e in entries)
          if (e.subject != subject) e
      ]);
}

/// Why the policy could not be shown.
enum MembersFailure {
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

/// Which [MembersFailure] a failed read of the policy is.
MembersFailure failureOf(Object error) => switch (error) {
      ApiException(statusCode: 500) => MembersFailure.serverError,
      MalformedResponseException() => MembersFailure.unreadable,
      PermissionDeniedException() => MembersFailure.forbidden,
      NotFoundException() => MembersFailure.missing,
      _ => MembersFailure.other,
    };

/// The installation argument every `room-authz` command takes. It is a path
/// on the server, so the app never knows it.
const installationPlaceholder = '<installation>';

/// Makes a room with no policy private. The card leaves that to the server,
/// because the first save would lock out everyone not yet listed.
String makePrivateCommand(String roomId) =>
    'soliplex-cli room-authz make-private $installationPlaceholder '
    '${_shellWord(roomId)}';

/// Lists every entry of the room's policy, including one whose rule no longer
/// compiles, which the API cannot return.
String showPolicyCommand(String roomId) =>
    'soliplex-cli room-authz show $installationPlaceholder '
    '${_shellWord(roomId)}';

/// Removes a stale rule. The API's failure names no entry, so the rule and its
/// permission come from [showPolicyCommand]'s output.
String deleteStaleRuleCommand(String roomId) =>
    'soliplex-cli room-authz delete-acl-entry $installationPlaceholder '
    "${_shellWord(roomId)} --allow --permission <permission> --json-path '<rule>' "
    '--allow-invalid-json-path';

/// [value] as one shell word: bare when it is plainly safe, single-quoted
/// otherwise.
String _shellWord(String value) =>
    RegExp(r'^[A-Za-z0-9._@%+=:,/-]+$').hasMatch(value)
        ? value
        : "'${value.replaceAll("'", r"'\''")}'";
