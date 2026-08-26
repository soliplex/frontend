import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_frontend/src/modules/auth/admin_status.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeSoliplexApi api;
  late AdminStatus status;

  setUp(() {
    api = FakeSoliplexApi();
    status = AdminStatus(api: api, serverId: 'test');
  });

  test('asks once and answers every later read from that', () async {
    api.nextIsAdminUser = true;

    expect(await status.read(), isTrue);
    expect(await status.read(), isTrue);

    // The backend writes an audit record per call, so a second ask is not a
    // wasted round trip but a spurious record.
    expect(api.getIsAdminUserCallCount, 1);
  });

  test('survives an error that is not an exception', () async {
    // A closed http client throws StateError from outside its own guard. If
    // that escaped, the rejected future would stay memoised and the caller
    // would never resolve.
    api.nextIsAdminUserThrow = StateError('client closed');

    expect(await status.read(), isNull);

    api.nextIsAdminUserThrow = null;
    api.nextIsAdminUser = true;
    expect(await status.read(), isTrue);
    expect(api.getIsAdminUserCallCount, 2);
  });

  test('a refusal answers, but is asked again next time', () async {
    // A 403 is the server answering, not failing to. Folding it into `null`
    // would hand the caller a grant, so the gate would loosen exactly as the
    // server tightened.
    api.nextIsAdminUserThrow = const PermissionDeniedException(
      message: 'forbidden',
      statusCode: 403,
    );

    expect(await status.read(), isFalse);
    expect(await status.read(), isFalse);
    // Asked again: within one screen the answer is shared, but a refusal is
    // the one verdict the client cannot attribute — the installation may have
    // said it, or something in front of it may have. Keeping it for the
    // session would leave an administrator refused by a gateway with no way
    // back short of restarting.
    expect(api.getIsAdminUserCallCount, 2);
  });

  test('two reads while a request is in flight both get the answer', () async {
    final gate = Completer<bool>();
    api.isAdminUserGate = gate;

    final first = status.read();
    final second = status.read();
    gate.complete(true);

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(api.getIsAdminUserCallCount, 1);
  });

  test('clear makes the next read ask again', () async {
    api.nextIsAdminUser = true;
    expect(await status.read(), isTrue);

    status.clear();
    api.nextIsAdminUser = false;

    expect(await status.read(), isFalse);
    expect(api.getIsAdminUserCallCount, 2);
  });

  test('an answer that lands after a clear is not delivered', () async {
    // It describes whoever was signed in when it was asked, so handing it to
    // the caller still awaiting would answer for the wrong user.
    final gate = Completer<bool>();
    api.isAdminUserGate = gate;
    final stale = status.read();

    status.clear();
    gate.complete(true);

    expect(await stale, isNull);
  });

  test('a failed request does not evict a newer one', () async {
    final first = Completer<bool>();
    api.isAdminUserGate = first;
    final stale = status.read();

    status.clear();
    api.isAdminUserGate = null;
    api.nextIsAdminUser = true;
    expect(await status.read(), isTrue);

    first.completeError(NetworkException(message: 'offline'));
    await stale;

    // The live answer is still remembered, so nothing re-asks.
    expect(await status.read(), isTrue);
    expect(api.getIsAdminUserCallCount, 2);
  });
}
