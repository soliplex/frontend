import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show AgUiStreamClient, SoliplexApi;
import 'package:test/test.dart';

class MockSoliplexApi extends Mock implements SoliplexApi {}

class MockAgUiStreamClient extends Mock implements AgUiStreamClient {}

ServerConnection _fakeConnection(String serverId) => ServerConnection(
  serverId: serverId,
  api: MockSoliplexApi(),
  agUiStreamClient: MockAgUiStreamClient(),
);

void main() {
  group('ServerRegistry', () {
    late ServerRegistry registry;

    setUp(() {
      registry = ServerRegistry();
    });

    test('add then lookup', () {
      final conn = _fakeConnection('srv-1');
      registry.add(conn);

      expect(registry['srv-1'], same(conn));
    });

    test('add duplicate throws StateError', () {
      registry.add(_fakeConnection('srv-1'));

      expect(() => registry.add(_fakeConnection('srv-1')), throwsStateError);
    });

    test('remove returns connection', () {
      final conn = _fakeConnection('srv-1');
      registry.add(conn);

      final removed = registry.remove('srv-1');

      expect(removed, same(conn));
      expect(registry['srv-1'], isNull);
    });

    test('remove absent returns null', () {
      expect(registry.remove('nope'), isNull);
    });

    test('operator [] absent returns null', () {
      expect(registry['nope'], isNull);
    });

    test('require present returns connection', () {
      final conn = _fakeConnection('srv-1');
      registry.add(conn);

      expect(registry.require('srv-1'), same(conn));
    });

    test('require absent throws StateError', () {
      expect(() => registry.require('nope'), throwsStateError);
    });

    test('serverIds reflects mutations', () {
      registry
        ..add(_fakeConnection('a'))
        ..add(_fakeConnection('b'));

      expect(registry.serverIds, containsAll(['a', 'b']));

      registry.remove('a');

      expect(registry.serverIds, ['b']);
    });

    test('connections reflects mutations', () {
      final connA = _fakeConnection('a');
      final connB = _fakeConnection('b');
      registry
        ..add(connA)
        ..add(connB);

      expect(registry.connections, containsAll([connA, connB]));

      registry.remove('a');

      expect(registry.connections, [connB]);
    });

    test('isEmpty and length', () {
      expect(registry.isEmpty, isTrue);
      expect(registry.length, 0);

      registry.add(_fakeConnection('srv-1'));

      expect(registry.isEmpty, isFalse);
      expect(registry.length, 1);
    });
  });
}
