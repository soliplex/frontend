import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/room_state.dart';

import '../../helpers/fakes.dart';

ServerConnection _fakeConnection(FakeSoliplexApi api) => ServerConnection(
      serverId: 'test-server',
      api: api,
      agUiStreamClient: FakeAgUiStreamClient(),
    );

void main() {
  late FakeSoliplexApi api;
  late ServerConnection connection;

  setUp(() {
    api = FakeSoliplexApi();
    connection = _fakeConnection(api);
  });

  test('selectThread creates ThreadViewState', () async {
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(connection: connection, roomId: 'room-1');
    expect(state.activeThreadView, isNull);

    state.selectThread('thread-1');
    expect(state.activeThreadView, isNotNull);
    expect(state.activeThreadView!.threadId, 'thread-1');

    state.dispose();
  });

  test('selectThread disposes previous ThreadViewState', () async {
    api.nextThreads = [];
    api.nextThreadHistory = ThreadHistory(messages: const []);

    final state = RoomState(connection: connection, roomId: 'room-1');

    state.selectThread('thread-1');
    final first = state.activeThreadView;

    state.selectThread('thread-2');
    expect(state.activeThreadView!.threadId, 'thread-2');
    expect(state.activeThreadView, isNot(same(first)));

    state.dispose();
  });
}
