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

Widget _card(_PolicyApi api, {Future<bool?> Function()? isAdmin}) =>
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: SingleChildScrollView(
          child: MembersCard(
            api: api,
            roomId: 'ops',
            isAdmin: isAdmin ?? () async => true,
            viewerClaims: () => {'email': 'me@example.com'},
          ),
        ),
      ),
    );

Future<void> _show(
  WidgetTester tester,
  _PolicyApi api, {
  Future<bool?> Function()? isAdmin,
  Size size = const Size(900, 1400),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_card(api, isAdmin: isAdmin));
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

    await tester.tap(find.text('Add people'));
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

    await tester.tap(find.text('Add people'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Member').last);
    await tester.pumpAndSettle();
    expect(find.text('Reader'), findsWidgets);
    expect(find.text('Admin'), findsOneWidget); // boss's badge, behind
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
    expect(find.text('Add people'), findsNothing);
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
      "This room's access holds entries this app can't read",
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
      "Couldn't read this room's access",
    ),
  ]) {
    testWidgets('explains ${error.runtimeType}', (tester) async {
      final api = _PolicyApi(_team())..readError = error;
      await _show(tester, api);
      await _open(tester);

      expect(find.text(title), findsOneWidget);
    });
  }

  testWidgets('says so when a save fails, and keeps the list', (
    tester,
  ) async {
    final api = _PolicyApi(_team())
      ..saveError = const ApiException(message: 'no', statusCode: 422);
    await _show(tester, api);
    await _open(tester);

    await tester.tap(find.byTooltip('Remove rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SoliplexButton, 'Remove rule'));
    await tester.pumpAndSettle();

    expect(
      find.text('The server refused this change. Nothing was changed.'),
      findsOneWidget,
    );
    expect(find.text('is_staff'), findsOneWidget);
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

    await tester.tap(find.text('Add people'));
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
    return super.getRoomPolicy(roomId, cancelToken: cancelToken);
  }
}
