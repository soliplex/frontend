import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_info/members/room_access.dart';

const _read = AccessPermission.read;
const _write = AccessPermission.write;
const _admin = AccessPermission.admin;

AccessSubject _email(String name) => AccessSubject.email('$name@example.com');

const _rule = AccessSubject.jsonPath(r'$[?is_staff($)]');

RoomPolicy _policy(List<AccessEntry> entries) => RoomPolicy(
      roomId: 'ops',
      defaultEffect: AccessEffect.deny,
      entries: entries,
    );

void main() {
  group('rows', () {
    final policy = _policy([
      AccessEntry(_email('a'), _read),
      AccessEntry(_email('a'), _write),
      AccessEntry(_email('b'), _read),
      const AccessEntry(_rule, _read),
      AccessEntry(_email('c'), _read),
      AccessEntry(_email('c'), _write),
      AccessEntry(_email('c'), _admin),
      AccessEntry(_email('d'), _write),
      AccessEntry(_email('e'), _read, effect: AccessEffect.deny),
      const AccessEntry(AccessSubject.authenticated(), _read),
      const AccessEntry(AccessSubject.jsonPath(r'$[?@.dept == "x"]'), _read),
      const AccessEntry(AccessSubject.preferredUsername('u1'), _read),
    ]);
    final rows = {for (final r in policy.rows) displayName(r.subject): r};

    test('read each subject once, as a role where one fits', () {
      expect(rows.keys, [
        'a@example.com',
        'b@example.com',
        'is_staff',
        'c@example.com',
        'd@example.com',
        'e@example.com',
        'Everyone signed in',
        r'$[?@.dept == "x"]',
        'u1',
      ]);
      expect(rows['a@example.com']!.role, RoomRole.member);
      expect(rows['b@example.com']!.role, RoomRole.reader);
      expect(rows['c@example.com']!.role, RoomRole.admin);
      expect(rows['d@example.com']!.role, isNull);
      expect(rows['e@example.com']!.role, isNull);
      expect(rows['e@example.com']!.hasDeny, isTrue);
    });

    test('put only plain people and rules in the editable groups', () {
      expect(rows['a@example.com']!.group, RowGroup.people);
      expect(rows['u1']!.group, RowGroup.people);
      expect(rows['is_staff']!.group, RowGroup.rules);
      expect(rows['d@example.com']!.group, RowGroup.other);
      expect(rows['e@example.com']!.group, RowGroup.other);
      expect(rows['Everyone signed in']!.group, RowGroup.other);
      expect(rows[r'$[?@.dept == "x"]']!.group, RowGroup.other);
    });

    test('summarise what is not a role in the server terms', () {
      expect(rows['d@example.com']!.rawSummary, 'Allowed write');
      expect(rows['e@example.com']!.rawSummary, 'Denied read');
    });

    test('match the viewer exactly, as the server does', () {
      final a = rows['a@example.com']!;
      expect(a.isViewer({'email': 'a@example.com'}), isTrue);
      expect(a.isViewer({'email': 'A@example.com'}), isFalse);
      expect(a.isViewer(null), isFalse);
      expect(rows['u1']!.isViewer({'preferred_username': 'u1'}), isTrue);
      expect(rows['is_staff']!.isViewer({'email': 'is_staff'}), isFalse);
    });
  });

  test('ruleName reads only the one-check form', () {
    expect(ruleName(_rule), 'is_staff');
    expect(ruleName(const AccessSubject.jsonPath(r'$[?a($) && b($)]')), isNull);
    expect(ruleName(const AccessSubject.email('x')), isNull);
    expect(displayName(const AccessSubject.everyone()), 'Everyone');
  });

  group('edits', () {
    test('add appends after a deny placed first', () {
      final deny = AccessEntry(_email('x'), _read, effect: AccessEffect.deny);
      final next = _policy([deny]).add([_email('n')], RoomRole.member);
      expect(next.entries, [
        deny,
        AccessEntry(_email('n'), _read),
        AccessEntry(_email('n'), _write),
      ]);
      expect(next.lists(_email('n')), isTrue);
      expect(next.roomId, 'ops');
    });

    test('setRole changes one subject in place', () {
      final policy = _policy([
        AccessEntry(_email('a'), _read),
        AccessEntry(_email('b'), _read),
        AccessEntry(_email('b'), _write),
        AccessEntry(_email('c'), _read),
      ]);

      expect(policy.setRole(_email('a'), RoomRole.member).entries, [
        AccessEntry(_email('a'), _read),
        AccessEntry(_email('a'), _write),
        AccessEntry(_email('b'), _read),
        AccessEntry(_email('b'), _write),
        AccessEntry(_email('c'), _read),
      ]);
      expect(policy.setRole(_email('b'), RoomRole.reader).entries, [
        AccessEntry(_email('a'), _read),
        AccessEntry(_email('b'), _read),
        AccessEntry(_email('c'), _read),
      ]);
    });

    test('remove drops every entry of the subject', () {
      final policy = _policy([
        AccessEntry(_email('a'), _read),
        const AccessEntry(_rule, _read),
        AccessEntry(_email('a'), _write),
      ]);
      expect(policy.remove(_email('a')).entries, const [
        AccessEntry(_rule, _read),
      ]);
    });
  });

  test('offers Reader and Member, never Admin', () {
    expect(RoomRole.offered, [RoomRole.reader, RoomRole.member]);
    expect(RoomRole.fromPermissions({_write}), isNull);
  });

  group('commands', () {
    test('carry the room ID', () {
      expect(
        makePrivateCommand('ops'),
        'soliplex-cli room-authz make-private <installation> ops',
      );
      expect(
        showPolicyCommand('ops'),
        'soliplex-cli room-authz show <installation> ops',
      );
      expect(
        deleteStaleRuleCommand('ops'),
        'soliplex-cli room-authz delete-acl-entry <installation> ops '
        "--allow --permission <permission> --json-path '<rule>' "
        '--allow-invalid-json-path',
      );
    });

    test('quote a room ID the shell would split', () {
      expect(
        showPolicyCommand("it's mine"),
        "soliplex-cli room-authz show <installation> 'it'\\''s mine'",
      );
    });
  });

  group('visibleRows', () {
    final rows = _policy([
      AccessEntry(_email('Ann'), _read),
      AccessEntry(_email('bob'), _read),
      AccessEntry(_email('bob'), _write),
      const AccessEntry(_rule, _read),
      AccessEntry(_email('cy'), _read),
      AccessEntry(_email('cy'), _write),
      AccessEntry(_email('cy'), _admin),
    ]).rows;
    List<String> names(List<MemberRow> rows) =>
        [for (final r in rows) displayName(r.subject)];

    test('filters by role and by rule', () {
      expect(
        names(visibleRows(rows, filter: MemberFilter.reader).matching),
        ['Ann@example.com', 'is_staff'],
      );
      expect(
        names(visibleRows(rows, filter: MemberFilter.member).matching),
        ['bob@example.com'],
      );
      expect(
        names(visibleRows(rows, filter: MemberFilter.admin).matching),
        ['cy@example.com'],
      );
      expect(
        names(visibleRows(rows, filter: MemberFilter.rules).matching),
        ['is_staff'],
      );
      expect(visibleRows(rows).matching, hasLength(4));
    });

    test('searches names, ignoring case and outer spaces', () {
      expect(
        names(visibleRows(rows, search: '  ANN ').matching),
        ['Ann@example.com'],
      );
      expect(
        names(visibleRows(rows, search: 'staff').matching),
        ['is_staff'],
      );
      expect(
        visibleRows(rows, filter: MemberFilter.member, search: 'ann').matching,
        isEmpty,
      );
    });

    test('shows the first page of what matches', () {
      final page = visibleRows(rows, limit: 2);
      expect(page.matching, hasLength(4));
      expect(names(page.shown), ['Ann@example.com', 'bob@example.com']);
      expect(visibleRows(rows, limit: 4).shown, hasLength(4));
      expect(visibleRows(rows).shown, hasLength(4));
    });
  });

  test('failureOf names what a failed read means', () {
    expect(
      failureOf(const ApiException(message: 'x', statusCode: 500)),
      MembersFailure.serverError,
    );
    expect(
      failureOf(const ApiException(message: 'x', statusCode: 502)),
      MembersFailure.other,
    );
    expect(
      failureOf(const MalformedResponseException(message: 'x')),
      MembersFailure.unreadable,
    );
    expect(
      failureOf(const PermissionDeniedException(message: 'x')),
      MembersFailure.forbidden,
    );
    expect(
      failureOf(const NotFoundException(message: 'x')),
      MembersFailure.missing,
    );
    expect(
      failureOf(const NetworkException(message: 'x')),
      MembersFailure.other,
    );
  });

  group('planEdit', () {
    final seen = _policy([
      AccessEntry(_email('a'), _read),
      AccessEntry(_email('a'), _write),
      AccessEntry(_email('b'), _read),
    ]);
    MemberRow rowOf(RoomPolicy policy, String name) =>
        policy.rows.firstWhere((r) => r.subject == _email(name));

    test('saves when the row is as the user saw it', () {
      final plan = planEdit(seen, SetRole(rowOf(seen, 'b'), RoomRole.member));
      expect(
        (plan as SaveEdit).next.entries,
        seen.setRole(_email('b'), RoomRole.member).entries,
      );
      expect(
        planEdit(seen, RemoveMember(rowOf(seen, 'a'))),
        isA<SaveEdit>(),
      );
    });

    test('stops when the subject was removed since', () {
      final fresh = seen.remove(_email('b'));
      expect(
        planEdit(fresh, SetRole(rowOf(seen, 'b'), RoomRole.member)),
        isA<RowChanged>().having((p) => p.subject, 'subject', _email('b')),
      );
      expect(
          planEdit(fresh, RemoveMember(rowOf(seen, 'b'))), isA<RowChanged>());
    });

    test('stops when a deny was added since, so it is never dropped', () {
      final fresh = seen.withEntries([
        ...seen.entries,
        AccessEntry(_email('a'), _admin, effect: AccessEffect.deny),
      ]);
      expect(
          planEdit(fresh, RemoveMember(rowOf(seen, 'a'))), isA<RowChanged>());
      expect(
        planEdit(fresh, SetRole(rowOf(seen, 'a'), RoomRole.reader)),
        isA<RowChanged>(),
      );
    });

    test('stops when the role changed since', () {
      final fresh = seen.setRole(_email('a'), RoomRole.reader);
      expect(
        planEdit(fresh, SetRole(rowOf(seen, 'a'), RoomRole.admin)),
        isA<RowChanged>(),
      );
    });

    test('stops a promotion over a deny', () {
      final fresh = seen.withEntries([
        AccessEntry(_email('b'), _write, effect: AccessEffect.deny),
        ...seen.entries,
      ]);
      expect(
        planEdit(fresh, SetRole(rowOf(seen, 'b'), RoomRole.member)),
        isA<RowChanged>(),
      );
    });

    test('adds only people not listed since', () {
      final plan = planEdit(
        seen,
        AddPeople([_email('a'), _email('n')], RoomRole.reader),
      );
      expect((plan as SaveEdit).next.entries.sublist(seen.entries.length), [
        AccessEntry(_email('n'), _read),
      ]);
    });
  });
}
