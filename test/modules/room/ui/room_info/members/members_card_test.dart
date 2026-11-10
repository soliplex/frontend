import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_info/members/members_card.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_info/members/room_access.dart';

import '../../../../../helpers/fakes.dart';

/// Answers the policy endpoints from memory, recording each save.
class _PolicyApi extends FakeSoliplexApi {
  _PolicyApi(this.policy);

  RoomPolicy? policy;
  Object? readError;
  Object? saveError;
  int reads = 0;
  final saved = <RoomPolicy>[];
  List<LoginCheck> checks = const [
    LoginCheck('is_staff', description: 'Match staff logins.'),
    LoginCheck('has_badge'),
  ];
  Object? checksError;
  int checkReads = 0;

  /// When set, the checks read waits for it.
  Completer<void>? checksGate;

  @override
  Future<List<LoginCheck>> getLoginChecks({CancelToken? cancelToken}) async {
    checkReads++;
    await checksGate?.future;
    if (checksError case final error?) throw error;
    return checks;
  }

  @override
  Future<RoomPolicy?> getRoomPolicy(
    String roomId, {
    CancelToken? cancelToken,
  }) async {
    reads++;
    if (readError case final error?) throw error;
    return policy;
  }

  @override
  Future<void> setRoomPolicy(
    RoomPolicy policy, {
    CancelToken? cancelToken,
  }) async {
    if (saveError case final error?) throw error;
    saved.add(policy);
    this.policy = policy;
  }
}

const _read = AccessPermission.read;
const _write = AccessPermission.write;

AccessSubject _email(String name) => AccessSubject.email('$name@example.com');

RoomPolicy _team({AccessEffect defaultEffect = AccessEffect.deny}) =>
    RoomPolicy(
      roomId: 'ops',
      defaultEffect: defaultEffect,
      entries: [
        AccessEntry(_email('me'), _read),
        AccessEntry(_email('me'), _write),
        AccessEntry(_email('jdoe'), _read),
        AccessEntry(_email('jdoe'), _write),
        AccessEntry(_email('cwong'), _read),
        AccessEntry(_email('boss'), _read),
        AccessEntry(_email('boss'), _write),
        AccessEntry(_email('boss'), AccessPermission.admin),
        const AccessEntry(AccessSubject.jsonPath(r'$[?is_staff($)]'), _read),
        AccessEntry(_email('gone'), _read, effect: AccessEffect.deny),
      ],
    );

Widget _card(
  _PolicyApi api, {
  Future<bool?> Function()? isAdmin,
  Map<String, dynamic>? claims = const {'email': 'me@example.com'},
}) =>
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MembersCard(
            api: api,
            roomId: 'ops',
            isAdmin: isAdmin ?? () async => true,
            viewerClaims: () => claims,
          ),
        ),
      ),
    );

Future<void> _show(
  WidgetTester tester,
  _PolicyApi api, {
  Future<bool?> Function()? isAdmin,
  Map<String, dynamic>? claims = const {'email': 'me@example.com'},
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_card(api, isAdmin: isAdmin, claims: claims));
  await tester.pumpAndSettle();
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('MEMBERS'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('is absent for anyone who is not a server admin', (
    tester,
  ) async {
    final api = _PolicyApi(_team());
    await _show(tester, api, isAdmin: () async => false);
    expect(find.text('MEMBERS'), findsNothing);

    await _show(tester, api, isAdmin: () async => null);
    expect(find.text('MEMBERS'), findsNothing);
    expect(api.reads, 0);
  });

  testWidgets('reads nothing until opened', (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    expect(find.text('MEMBERS'), findsOneWidget);
    expect(api.reads, 0);

    await _open(tester);
    expect(api.reads, 1);
    expect(find.text('MEMBERS (6)'), findsOneWidget);
    expect(find.text('Private'), findsOneWidget);
    expect(find.textContaining('People', findRichText: true), findsOneWidget);
    expect(
      find.textContaining('Login rules', findRichText: true),
      findsOneWidget,
    );
    expect(
      find.textContaining('Set outside this card', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('is_staff'), findsOneWidget);
    expect(find.text('Denied read'), findsOneWidget);
  });

  testWidgets("locks the viewer's own row", (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    expect(find.text('You'), findsOneWidget);
    // jdoe, cwong, boss and the rule; not the viewer, not the deny.
    expect(find.byTooltip('Remove'), findsNWidgets(3));
    expect(find.byTooltip('Remove rule'), findsOneWidget);
  });

  testWidgets('adds people as Members by default', (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    await tester.tap(find.text('Add access'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'new@example.com, Odd@example.com jdoe@example.com nope',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('already Member'), findsOneWidget);
    expect(find.textContaining('not an address'), findsOneWidget);
    expect(find.textContaining('capitals must match'), findsOneWidget);
    expect(find.text('2 to add, 2 skipped.'), findsOneWidget);

    await tester.tap(find.text('Add 2 people'));
    await tester.pumpAndSettle();

    final saved = api.saved.single;
    expect(saved.entries.sublist(_team().entries.length), [
      AccessEntry(_email('new'), _read),
      AccessEntry(_email('new'), _write),
      const AccessEntry(AccessSubject.email('Odd@example.com'), _read),
      const AccessEntry(AccessSubject.email('Odd@example.com'), _write),
    ]);
    expect(find.text('Added 2 people as Member.'), findsOneWidget);
    expect(find.text('MEMBERS (8)'), findsOneWidget);
  });

  testWidgets('offers Reader and Member, not Admin', (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    await tester.tap(find.text('Add access'));
    await tester.pumpAndSettle();
    // The menu also builds its entries under the field, to size it; only
    // the open menu's entries can be tapped.
    Finder entries([String? label]) {
      final buttons = find.byType(MenuItemButton).hitTestable();
      return label == null
          ? buttons
          : find.descendant(of: buttons, matching: find.text(label));
    }

    expect(entries(), findsNothing);
    await tester.tap(find.byType(SoliplexDropdown<RoomRole>));
    await tester.pumpAndSettle();

    expect(entries('Reader'), findsOneWidget);
    expect(entries('Member'), findsOneWidget);
    expect(entries(), findsNWidgets(2));
  });

  testWidgets('changes a role in place', (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    // cwong, listed before the rule, which is the other Reader.
    await tester.tap(find.text('Reader').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Member').last);
    await tester.pumpAndSettle();

    final entries = api.saved.single.entries;
    expect(
      entries.indexOf(AccessEntry(_email('cwong'), _write)),
      entries.indexOf(AccessEntry(_email('cwong'), _read)) + 1,
    );
    expect(find.text('cwong@example.com is now Member.'), findsOneWidget);
  });

  testWidgets('confirms before taking Admin away', (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader').last);
    await tester.pumpAndSettle();
    expect(find.text('Make boss@example.com a Reader?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.saved, isEmpty);

    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reader').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Change role'));
    await tester.pumpAndSettle();
    expect(
      api.saved.single.entries.where((e) => e.subject == _email('boss')),
      [AccessEntry(_email('boss'), _read)],
    );
  });

  testWidgets('removes after confirming', (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    await tester.tap(find.byTooltip('Remove rule'));
    await tester.pumpAndSettle();
    expect(find.text('Remove the rule is_staff?'), findsOneWidget);
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove rule'));
    await tester.pumpAndSettle();

    expect(
      api.saved.single.entries.map((e) => e.subject),
      isNot(contains(const AccessSubject.jsonPath(r'$[?is_staff($)]'))),
    );
    expect(find.text('Removed is_staff.'), findsOneWidget);
  });

  testWidgets('warns that removal does not revoke reading in an open room', (
    tester,
  ) async {
    final api = _PolicyApi(_team(defaultEffect: AccessEffect.allow));
    await _show(tester, api);
    await _open(tester);

    expect(find.text('Open to read'), findsOneWidget);
    expect(find.textContaining('removing someone does not stop'), findsOne);
  });

  testWidgets('leaves a public room to the server', (tester) async {
    final api = _PolicyApi(null);
    await _show(tester, api);
    await _open(tester);

    expect(find.text('Public'), findsOneWidget);
    expect(find.text('Add access'), findsNothing);
    expect(
      find.text('soliplex-cli room-authz make-private <installation> ops'),
      findsOneWidget,
    );
  });

  testWidgets('gives the commands for a stale rule', (tester) async {
    final api = _PolicyApi(_team())
      ..readError = const ApiException(
        message: 'Internal Server Error',
        statusCode: 500,
      );
    await _show(tester, api);
    await _open(tester);

    expect(
      find.text("The server couldn't read this room's access"),
      findsOneWidget,
    );
    expect(
      find.text('soliplex-cli room-authz show <installation> ops'),
      findsOneWidget,
    );
    expect(
      find.textContaining('delete-acl-entry <installation> ops'),
      findsOneWidget,
    );

    api.readError = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Private'), findsOneWidget);
  });

  for (final (error, title) in [
    (
      const MalformedResponseException(message: 'bad'),
      "The server's answer about this room's access couldn't be read",
    ),
    (
      const PermissionDeniedException(message: 'no'),
      "The server didn't let you read this room's access",
    ),
    (
      const NotFoundException(message: 'no'),
      "This server can't show room access",
    ),
    (
      const NetworkException(message: 'down'),
      "Couldn't reach the server",
    ),
    (
      const AuthException(message: 'expired', statusCode: 401),
      'Your session has expired',
    ),
  ]) {
    testWidgets('explains ${error.runtimeType}', (tester) async {
      final api = _PolicyApi(_team())..readError = error;
      await _show(tester, api);
      await _open(tester);

      expect(find.text(title), findsOneWidget);
    });
  }

  testWidgets('says so when a save fails, and shows the policy as last read', (
    tester,
  ) async {
    final api = _PolicyApi(_team())
      ..saveError = const ApiException(message: 'no', statusCode: 422);
    await _show(tester, api);
    await _open(tester);

    // Another administrator adds someone while the list is open.
    api.policy = api.policy!.add(
      [const AccessSubject.email('new@example.com')],
      RoomRole.reader,
    );
    await tester.tap(find.byTooltip('Remove rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove rule'));
    await tester.pumpAndSettle();

    expect(
      find.text('The server refused this change. Nothing was changed.'),
      findsOneWidget,
    );
    expect(find.text('is_staff'), findsOneWidget);
    // Shown as read just before the save, not as first opened.
    expect(find.text('new@example.com'), findsOneWidget);
  });

  testWidgets('stops when the room became public before a save', (
    tester,
  ) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    api.policy = null;
    await tester.tap(find.byTooltip('Remove rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove rule'));
    await tester.pumpAndSettle();

    expect(api.saved, isEmpty);
    expect(find.text('Public'), findsOneWidget);
    expect(
      find.text(
        'This room became public in the meantime. Nothing was changed.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('saves nothing when the row changed since it was shown', (
    tester,
  ) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    // Another administrator demotes jdoe while the list is open.
    api.policy = api.policy!.withEntries([
      for (final e in api.policy!.entries)
        if (e != AccessEntry(_email('jdoe'), _write)) e,
    ]);
    await tester.tap(find.byTooltip('Remove').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(api.saved, isEmpty);
    expect(
      find.text(
        'jdoe@example.com changed since you opened this. Check it and try '
        'again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Reader'), findsWidgets);
  });

  testWidgets('says so when everyone being added was listed since', (
    tester,
  ) async {
    final api = _PolicyApi(_team());
    await _show(tester, api);
    await _open(tester);

    await tester.tap(find.text('Add access'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'late@example.com');
    await tester.pumpAndSettle();
    // Another administrator adds the same person first.
    api.policy = api.policy!.add(
      [const AccessSubject.email('late@example.com')],
      RoomRole.reader,
    );
    await tester.tap(find.text('Add person'));
    await tester.pumpAndSettle();

    expect(api.saved, isEmpty);
    expect(
      find.text('Nothing to change: the list already says so.'),
      findsOneWidget,
    );
    expect(find.text('late@example.com'), findsOneWidget);
  });

  testWidgets('logs the status and the reason of a failure', (tester) async {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    const failure =
        ApiException(message: 'Internal Server Error', statusCode: 500);
    final api = _PolicyApi(_team())..readError = failure;
    await _show(tester, api);
    await _open(tester);

    final record =
        sink.records.singleWhere((r) => r.message == 'Room policy read failed');
    expect(record.error, same(failure));
    expect(record.attributes['statusCode'], 500);
    expect(record.attributes['roomId'], 'ops');
  });

  testWidgets('ends a read that fails outside the client in the failed state', (
    tester,
  ) async {
    final api = _PolicyApi(_team())..readError = StateError('closed');
    await _show(tester, api);
    await _open(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('says so when a save fails outside the client', (tester) async {
    final api = _PolicyApi(_team())..saveError = StateError('closed');
    await _show(tester, api);
    await _open(tester);

    await tester.tap(find.byTooltip('Remove rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove rule'));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't save. Nothing was changed."), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });

  testWidgets("says when it can't tell which entry is yours", (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api, claims: null);
    await _open(tester);

    expect(find.textContaining("can't tell which entry is yours"), findsOne);
    expect(find.text('You'), findsNothing);
  });

  testWidgets('says nothing about that when it can', (tester) async {
    await _show(tester, _PolicyApi(_team()));
    await _open(tester);

    expect(
        find.textContaining("can't tell which entry is yours"), findsNothing);
  });

  testWidgets('searches a long list', (tester) async {
    final api = _PolicyApi(
      RoomPolicy(
        roomId: 'ops',
        defaultEffect: AccessEffect.deny,
        entries: [
          for (var i = 0; i < 30; i++)
            AccessEntry(_email('p${i.toString().padLeft(2, '0')}'), _read),
        ],
      ),
    );
    await _show(tester, api, size: const Size(900, 4000));
    await _open(tester);

    expect(find.text('Show all 30'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'p2');
    await tester.pumpAndSettle();
    expect(find.textContaining('@example.com'), findsNWidgets(10));

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear search and filters'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show all 30'));
    await tester.pumpAndSettle();
    expect(find.textContaining('@example.com'), findsNWidgets(30));
  });

  testWidgets('fits a phone', (tester) async {
    final api = _PolicyApi(_team());
    await _show(tester, api, size: const Size(360, 1600));
    await _open(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('You'), findsOneWidget);
  });

  testWidgets('cancels its read when it leaves', (tester) async {
    final gate = Completer<void>();
    final api = _GatedApi(_team(), gate);
    await _show(tester, api);
    await tester.tap(find.text('MEMBERS'));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    gate.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  group('login rules', () {
    Future<void> openRules(WidgetTester tester) async {
      await tester.tap(find.text('Add access'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Login rule'));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps typed addresses across a switch to rules and back', (
      tester,
    ) async {
      final api = _PolicyApi(_team());
      await _show(tester, api);
      await _open(tester);
      await tester.tap(find.text('Add access'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Email addresses'),
        'new@example.com',
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Login rule'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('People'));
      await tester.pumpAndSettle();

      // What the field shows is what the button adds.
      expect(
        tester
            .widget<TextField>(
                find.widgetWithText(TextField, 'Email addresses'))
            .controller
            ?.text,
        'new@example.com',
      );
      expect(find.text('Add person'), findsOneWidget);
    });

    testWidgets('a rule row says what its check does', (tester) async {
      final api = _PolicyApi(_team());
      await _show(tester, api);
      await _open(tester);

      expect(api.checkReads, 1);
      expect(find.text('Match staff logins.'), findsOneWidget);
      expect(find.text('Checked at sign-in'), findsNothing);
    });

    testWidgets('checks are not asked for a room without rules', (
      tester,
    ) async {
      final api = _PolicyApi(
        RoomPolicy(
          roomId: 'ops',
          defaultEffect: AccessEffect.deny,
          entries: [AccessEntry(_email('me'), _read)],
        ),
      );
      await _show(tester, api);
      await _open(tester);
      expect(api.checkReads, 0);

      await openRules(tester);
      expect(api.checkReads, 1);
      expect(find.text('is_staff'), findsOneWidget);
    });

    testWidgets('a rule row keeps its plain subtitle when checks fail', (
      tester,
    ) async {
      final api = _PolicyApi(_team())
        ..checksError = const ApiException(message: 'x', statusCode: 500);
      await _show(tester, api);
      await _open(tester);

      expect(find.text('Checked at sign-in'), findsOneWidget);
    });

    testWidgets('asks again for failed checks only on Try again', (
      tester,
    ) async {
      final api = _PolicyApi(_team())
        ..checksError = const ApiException(message: 'x', statusCode: 500);
      await _show(tester, api);
      await _open(tester);
      expect(api.checkReads, 1);

      // A save shows the policy again, which must not ask again.
      await tester.tap(find.text('Reader').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Member').last);
      await tester.pumpAndSettle();
      expect(api.saved, hasLength(1));
      expect(api.checkReads, 1);

      await openRules(tester);
      expect(find.text("Couldn't load the server's checks."), findsOneWidget);
      expect(api.checkReads, 1);

      api.checksError = null;
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(api.checkReads, 2);
      expect(find.text('has_badge'), findsOneWidget);
    });

    testWidgets('adds a rule picked from the server\'s checks', (
      tester,
    ) async {
      final api = _PolicyApi(_team());
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);

      expect(find.text('Pick a check.'), findsOneWidget);
      expect(find.text('No description given'), findsOneWidget);
      expect(
        find.text('Match staff logins. · already Reader'),
        findsOneWidget,
      );
      // Listed already, so it can't be picked.
      await tester.tap(find.text('Match staff logins. · already Reader'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a check.'), findsOneWidget);

      await tester.tap(find.text('has_badge'));
      await tester.pumpAndSettle();
      expect(find.text('Pick a check.'), findsNothing);
      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();

      expect(api.saved.single.entries.sublist(_team().entries.length), const [
        AccessEntry(AccessSubject.jsonPath(r'$[?has_badge($)]'), _read),
        AccessEntry(AccessSubject.jsonPath(r'$[?has_badge($)]'), _write),
      ]);
      expect(find.text('Added the has_badge rule as Member.'), findsOneWidget);
      // Read once for the rows; the dialog reused it.
      expect(api.checkReads, 1);
    });

    testWidgets('leaves out a check whose name a rule cannot hold', (
      tester,
    ) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final api = _PolicyApi(_team())
        ..checks = const [LoginCheck('has-dash'), LoginCheck('ok_name')];
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);
      // Rebuilds don't log it again.
      await tester.tap(find.text('ok_name'));
      await tester.pumpAndSettle();

      expect(find.text('ok_name'), findsOneWidget);
      expect(find.text('has-dash'), findsNothing);
      final record = sink.records.singleWhere(
        (r) => r.message == 'Login checks a rule cannot name',
      );
      expect(record.attributes['names'], ['has-dash']);
    });

    testWidgets("says when no check's name can be stored as a rule", (
      tester,
    ) async {
      final api = _PolicyApi(_team())..checks = const [LoginCheck('has-dash')];
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);

      expect(
        find.textContaining("names this app can't store as a rule"),
        findsOneWidget,
      );
      expect(find.textContaining('no checks registered'), findsNothing);
    });

    testWidgets('searches a long list of checks', (tester) async {
      final api = _PolicyApi(_team())
        ..checks = [
          for (var i = 0; i < 7; i++) LoginCheck('check_$i'),
          const LoginCheck('is_staff', description: 'Match staff logins.'),
        ];
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);

      final search = find.widgetWithText(TextField, 'Search checks');
      await tester.enterText(search, 'STAFF');
      await tester.pumpAndSettle();
      expect(find.text('check_0'), findsNothing);
      expect(find.text('is_staff'), findsWidgets);

      await tester.enterText(search, 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No check matches this search.'), findsOneWidget);
    });

    testWidgets('says when the server has no checks', (tester) async {
      final api = _PolicyApi(_team())..checks = const [];
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);

      expect(
        find.textContaining('The server has no checks registered'),
        findsOneWidget,
      );
      expect(find.text('Add rule'), findsOneWidget);
    });

    testWidgets('says when the server is too old to list checks', (
      tester,
    ) async {
      final api = _PolicyApi(_team())
        ..checksError = const NotFoundException(message: 'x');
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);

      expect(find.textContaining("can't list its checks"), findsOneWidget);
      // Asking again won't change the server's version.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('says why the checks could not be read', (tester) async {
      for (final (error, text) in <(Object, String)>[
        (
          const AuthException(message: 'x'),
          'Your session has expired. Sign in again, then try again.',
        ),
        (
          const PermissionDeniedException(message: 'x'),
          "The server didn't let you list its checks.",
        ),
        (
          const NetworkException(message: 'x'),
          "Couldn't reach the server. Check your connection and try again.",
        ),
        (
          const MalformedResponseException(message: 'x'),
          "The server's list of checks couldn't be read.",
        ),
        (
          const ApiException(message: 'x', statusCode: 500),
          "Couldn't load the server's checks.",
        ),
        (StateError('closed'), "Couldn't load the server's checks."),
      ]) {
        final api = _PolicyApi(_team())..checksError = error;
        await _show(tester, api);
        await _open(tester);
        await openRules(tester);

        expect(find.text(text), findsOneWidget, reason: '$error');
        expect(find.text('Try again'), findsOneWidget, reason: '$error');
        // A fresh card for the next error.
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('tries the checks again after a failure', (tester) async {
      final api = _PolicyApi(_team())
        ..checksError = const ApiException(message: 'x', statusCode: 503);
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);

      expect(find.text("Couldn't load the server's checks."), findsOneWidget);
      api
        ..checksError = null
        ..checksGate = Completer<void>();
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text("Couldn't load the server's checks."), findsNothing);
      expect(find.text('Try again'), findsNothing);

      api.checksGate!.complete();
      await tester.pumpAndSettle();
      expect(find.text('has_badge'), findsOneWidget);
    });

    // The rule rows behind the dialog carry the same names.
    Finder inDialog(String text) => find.descendant(
          of: find.byType(Dialog),
          matching: find.text(text),
        );

    VoidCallback? addRule(WidgetTester tester) => tester
        .widget<SoliplexButton>(find.widgetWithText(SoliplexButton, 'Add rule'))
        .onPressed;

    testWidgets('adds a rule with the role picked', (tester) async {
      final api = _PolicyApi(_team());
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);
      expect(addRule(tester), isNull);

      await tester.tap(find.byType(SoliplexDropdown<RoomRole>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(MenuItemButton).hitTestable(),
          matching: find.text('Reader'),
        ),
      );
      await tester.pumpAndSettle();
      // Listed already, so it can't be picked.
      await tester.tap(inDialog('is_staff'));
      await tester.pumpAndSettle();
      expect(addRule(tester), isNull);

      await tester.tap(find.text('has_badge'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add rule'));
      await tester.pumpAndSettle();

      expect(api.saved.single.entries.sublist(_team().entries.length), const [
        AccessEntry(AccessSubject.jsonPath(r'$[?has_badge($)]'), _read),
      ]);
      expect(find.text('Added the has_badge rule as Reader.'), findsOneWidget);
    });

    testWidgets('logs a failed checks read by its shape alone', (
      tester,
    ) async {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      const serverError = ApiException(message: 'x', statusCode: 500);
      for (final error in <Object>[serverError, StateError('closed')]) {
        sink.clear();
        final api = _PolicyApi(_team())..checksError = error;
        await _show(tester, api);
        await _open(tester);

        final record = sink.records
            .singleWhere((r) => r.message == 'Login checks read failed');
        if (error is ApiException) {
          expect(record.error, same(serverError));
          expect(record.attributes['statusCode'], 500);
        } else {
          expect(record.error, isNull);
          // The type alone: the error's own text ('closed') never reaches it.
          expect(record.attributes['failure'], 'StateError');
        }
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('searches checks by description too', (tester) async {
      final api = _PolicyApi(_team())
        ..checks = [
          for (var i = 0; i < 7; i++) LoginCheck('check_$i'),
          const LoginCheck('is_staff', description: 'Match staff logins.'),
        ];
      await _show(tester, api);
      await _open(tester);
      await openRules(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Search checks'),
        'LOGINS',
      );
      await tester.pumpAndSettle();
      expect(inDialog('is_staff'), findsOneWidget);
      expect(inDialog('check_0'), findsNothing);
    });

    testWidgets('offers a search from seven usable checks', (tester) async {
      for (final (count, shown) in [(6, findsNothing), (7, findsOneWidget)]) {
        final api = _PolicyApi(_team())
          ..checks = [
            for (var i = 0; i < count; i++) LoginCheck('check_$i'),
            // Not usable, so not counted.
            const LoginCheck('has-dash'),
          ];
        await _show(tester, api);
        await _open(tester);
        await openRules(tester);

        expect(
          find.widgetWithText(TextField, 'Search checks'),
          shown,
          reason: '$count checks',
        );
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets("a rule row whose check the server doesn't list stays plain", (
      tester,
    ) async {
      final api = _PolicyApi(_team())
        ..checks = const [LoginCheck('has_badge', description: 'Badge.')];
      await _show(tester, api);
      await _open(tester);

      expect(api.checkReads, 1);
      expect(find.text('Checked at sign-in'), findsOneWidget);
    });
  });
}

class _GatedApi extends _PolicyApi {
  _GatedApi(super.policy, this.gate);

  final Completer<void> gate;

  @override
  Future<RoomPolicy?> getRoomPolicy(
    String roomId, {
    CancelToken? cancelToken,
  }) async {
    await gate.future;
    // As the transport does: the token is checked once the answer arrives.
    cancelToken?.throwIfCancelled();
    return super.getRoomPolicy(roomId, cancelToken: cancelToken);
  }
}
