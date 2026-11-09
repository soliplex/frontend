import 'package:meta/meta.dart';

/// Whether an [AccessEntry] grants its permission or refuses it.
enum AccessEffect {
  /// Grants the permission.
  allow,

  /// Refuses the permission.
  deny,
}

/// What an [AccessEntry] grants or refuses.
///
/// The server never lets one permission imply another: a user holds `write`
/// only through an entry for `write`, whatever else they hold.
enum AccessPermission {
  /// Open the room and chat in it.
  read,

  /// Add and remove the room's uploaded files.
  write,

  /// Administer the room. Nothing on the server checks it yet.
  admin,
}

/// Which part of a user's login an [AccessSubject] matches.
enum AccessSubjectKind {
  /// Anyone, signed in or not.
  everyone,

  /// Anyone signed in.
  authenticated,

  /// The `preferred_username` claim, compared exactly.
  preferredUsername,

  /// The `email` claim, compared exactly, case included.
  email,

  /// A JSONPath query over the login's claims.
  jsonPath,
}

/// Who one [AccessEntry] is about: the wire's "exactly one discriminator".
@immutable
class AccessSubject {
  /// Anyone, signed in or not.
  const AccessSubject.everyone()
      : kind = AccessSubjectKind.everyone,
        value = null;

  /// Anyone signed in.
  const AccessSubject.authenticated()
      : kind = AccessSubjectKind.authenticated,
        value = null;

  /// The login whose `preferred_username` claim is [username].
  const AccessSubject.preferredUsername(String username)
      : kind = AccessSubjectKind.preferredUsername,
        value = username;

  /// The login whose `email` claim is [email].
  const AccessSubject.email(String email)
      : kind = AccessSubjectKind.email,
        value = email;

  /// The logins whose claims match the JSONPath [query].
  const AccessSubject.jsonPath(String query)
      : kind = AccessSubjectKind.jsonPath,
        value = query;

  /// Which claim this subject matches.
  final AccessSubjectKind kind;

  /// The claim value or query; null for [AccessSubjectKind.everyone] and
  /// [AccessSubjectKind.authenticated].
  final String? value;

  @override
  bool operator ==(Object other) =>
      other is AccessSubject && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);

  @override
  String toString() => 'AccessSubject(${kind.name})';
}

/// One row of a [RoomPolicy]: a subject, one permission, and whether it is
/// granted or refused.
@immutable
class AccessEntry {
  /// Creates an entry; it grants unless [effect] says otherwise.
  const AccessEntry(
    this.subject,
    this.permission, {
    this.effect = AccessEffect.allow,
  });

  /// Who the entry is about.
  final AccessSubject subject;

  /// What it grants or refuses.
  final AccessPermission permission;

  /// Whether it grants or refuses.
  final AccessEffect effect;

  @override
  bool operator ==(Object other) =>
      other is AccessEntry &&
      other.subject == subject &&
      other.permission == permission &&
      other.effect == effect;

  @override
  int get hashCode => Object.hash(subject, permission, effect);
}

/// Who may do what in one room, as `/v1/rooms/{room_id}/authz` holds it.
///
/// The server checks [entries] in order and the first that matches the user
/// and the permission decides. When none matches, [defaultEffect] decides
/// `read`; `write` and `admin` are refused.
@immutable
class RoomPolicy {
  /// Creates a policy for [roomId].
  RoomPolicy({
    required this.roomId,
    required this.defaultEffect,
    required List<AccessEntry> entries,
  }) : entries = List.unmodifiable(entries);

  /// The room the policy belongs to.
  final String roomId;

  /// What decides `read` when no entry matches.
  final AccessEffect defaultEffect;

  /// The entries, in the order the server checks them.
  final List<AccessEntry> entries;

  /// A copy holding [entries] in place of this policy's.
  RoomPolicy withEntries(List<AccessEntry> entries) => RoomPolicy(
        roomId: roomId,
        defaultEffect: defaultEffect,
        entries: entries,
      );
}
