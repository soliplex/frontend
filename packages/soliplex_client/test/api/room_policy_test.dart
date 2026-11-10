import 'package:mocktail/mocktail.dart';
import 'package:soliplex_client/soliplex_client.dart' hide CancelToken;
import 'package:soliplex_client/src/api/mappers.dart';
import 'package:soliplex_client/src/utils/cancel_token.dart';
import 'package:test/test.dart';

class MockHttpTransport extends Mock implements HttpTransport {}

void main() {
  group('roomPolicyFromJson', () {
    test('reads every subject kind, in order', () {
      final policy = roomPolicyFromJson({
        'room_id': 'ops',
        'default_allow_deny': 'allow',
        'acl_entries': [
          {'allow_deny': 'deny', 'permission': 'read', 'everyone': true},
          {
            'allow_deny': 'allow',
            'permission': 'write',
            'authenticated': true,
            'email': null,
          },
          {
            'allow_deny': 'allow',
            'permission': 'admin',
            'preferred_username': 'jdoe',
          },
          {'allow_deny': 'allow', 'permission': 'read', 'email': 'a@b.example'},
          {
            'allow_deny': 'allow',
            'permission': 'read',
            'json_path': r'$[?is_staff($)]',
          },
        ],
      });

      expect(policy.roomId, 'ops');
      expect(policy.defaultEffect, AccessEffect.allow);
      expect(policy.entries, const [
        AccessEntry(
          AccessSubject.everyone(),
          AccessPermission.read,
          effect: AccessEffect.deny,
        ),
        AccessEntry(AccessSubject.authenticated(), AccessPermission.write),
        AccessEntry(
          AccessSubject.preferredUsername('jdoe'),
          AccessPermission.admin,
        ),
        AccessEntry(AccessSubject.email('a@b.example'), AccessPermission.read),
        AccessEntry(
          AccessSubject.jsonPath(r'$[?is_staff($)]'),
          AccessPermission.read,
        ),
      ]);
    });

    test("takes the server's defaults for absent fields", () {
      final policy = roomPolicyFromJson({
        'room_id': 'ops',
        'acl_entries': [
          {'email': 'a@b.example'},
        ],
      });

      expect(policy.defaultEffect, AccessEffect.deny);
      expect(policy.entries.single.effect, AccessEffect.deny);
      expect(policy.entries.single.permission, AccessPermission.read);
    });

    test('refuses what a save would drop', () {
      Map<String, dynamic> withEntry(Map<String, dynamic> entry) => {
            'room_id': 'ops',
            'acl_entries': [entry],
          };

      for (final bad in [
        withEntry({'permission': 'execute', 'email': 'a@b.example'}),
        withEntry({'allow_deny': 'maybe', 'email': 'a@b.example'}),
        withEntry({'email': 'a@b.example', 'everyone': true}),
        withEntry({'permission': 'read'}),
        withEntry({'email': 42}),
        {
          'room_id': 'ops',
          'acl_entries': ['not an object'],
        },
        {'room_id': 'ops', 'acl_entries': 'nope'},
        {'acl_entries': <Object>[]},
      ]) {
        expect(
          () => roomPolicyFromJson(bad),
          throwsFormatException,
          reason: '$bad',
        );
      }
    });

    test('refuses an unknown key, which a save would drop', () {
      expect(
        () => roomPolicyFromJson({'room_id': 'ops', 'version': 3}),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'room policy has an unknown field "version"',
          ),
        ),
      );
      expect(
        () => roomPolicyFromJson({
          'room_id': 'ops',
          'acl_entries': [
            {'email': 'a@b.example', 'note': 'who knows'},
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(contains('"note"'), isNot(contains('who knows'))),
          ),
        ),
      );
    });

    test('names the field, never the value', () {
      expect(
        () => roomPolicyFromJson({
          'room_id': 'ops',
          'acl_entries': [
            {'email': 'a@b.example', 'preferred_username': 'secret-ish'},
          ],
        }),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            allOf(isNot(contains('a@b.example')), isNot(contains('secret'))),
          ),
        ),
      );
    });
  });

  group('roomPolicyToJson', () {
    test('round-trips, naming one subject per entry', () {
      final json = {
        'room_id': 'ops',
        'default_allow_deny': 'deny',
        'acl_entries': [
          {'allow_deny': 'deny', 'permission': 'read', 'everyone': true},
          {'allow_deny': 'allow', 'permission': 'read', 'authenticated': true},
          {
            'allow_deny': 'allow',
            'permission': 'write',
            'preferred_username': 'jdoe',
          },
          {'allow_deny': 'allow', 'permission': 'read', 'email': 'a@b.example'},
          {
            'allow_deny': 'allow',
            'permission': 'admin',
            'json_path': r'$[?is_staff($)]',
          },
        ],
      };

      expect(roomPolicyToJson(roomPolicyFromJson(json)), json);
    });
  });

  group('SoliplexApi room policy', () {
    late MockHttpTransport transport;
    late SoliplexApi api;
    final uri = Uri.parse('https://api.example.com/api/v1/rooms/ops/authz');

    setUpAll(() {
      registerFallbackValue(Uri.parse('https://example.com'));
      registerFallbackValue(CancelToken());
    });

    setUp(() {
      transport = MockHttpTransport();
      when(() => transport.close()).thenReturn(null);
      api = SoliplexApi(
        transport: transport,
        urlBuilder: UrlBuilder('https://api.example.com/api/v1'),
      );
    });

    tearDown(() => api.close());

    test('getRoomPolicy reads through the policy mapper', () async {
      final policy = RoomPolicy(
        roomId: 'ops',
        defaultEffect: AccessEffect.deny,
        entries: const [],
      );
      when(
        () => transport.request<RoomPolicy?>(
          'GET',
          uri,
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
        ),
      ).thenAnswer((_) async => policy);

      expect(await api.getRoomPolicy('ops'), same(policy));
      final mapper = verify(
        () => transport.request<RoomPolicy?>(
          'GET',
          uri,
          cancelToken: any(named: 'cancelToken'),
          fromJson: captureAny(named: 'fromJson'),
        ),
      ).captured.single as RoomPolicy Function(Map<String, dynamic>);
      expect(mapper({'room_id': 'ops'}).roomId, 'ops');
    });

    test('getRoomPolicy passes on a room with no policy', () async {
      when(
        () => transport.request<RoomPolicy?>(
          'GET',
          uri,
          cancelToken: any(named: 'cancelToken'),
          fromJson: any(named: 'fromJson'),
        ),
      ).thenAnswer((_) async => null);

      expect(await api.getRoomPolicy('ops'), isNull);
    });

    test('getRoomPolicy refuses an empty room ID', () {
      expect(() => api.getRoomPolicy(''), throwsArgumentError);
    });

    test('setRoomPolicy posts the whole policy', () async {
      when(
        () => transport.request<void>(
          'POST',
          uri,
          body: any(named: 'body'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).thenAnswer((_) async {});

      await api.setRoomPolicy(
        RoomPolicy(
          roomId: 'ops',
          defaultEffect: AccessEffect.deny,
          entries: const [
            AccessEntry(
              AccessSubject.email('a@b.example'),
              AccessPermission.read,
            ),
          ],
        ),
      );

      final body = verify(
        () => transport.request<void>(
          'POST',
          uri,
          body: captureAny(named: 'body'),
          cancelToken: any(named: 'cancelToken'),
        ),
      ).captured.single;
      expect(body, {
        'room_id': 'ops',
        'default_allow_deny': 'deny',
        'acl_entries': [
          {'allow_deny': 'allow', 'permission': 'read', 'email': 'a@b.example'},
        ],
      });
    });

    test('setRoomPolicy refuses an empty room ID', () {
      expect(
        () => api.setRoomPolicy(
          RoomPolicy(
            roomId: '',
            defaultEffect: AccessEffect.deny,
            entries: const [],
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('RoomPolicy', () {
    test('withEntries keeps the room and default', () {
      final policy = RoomPolicy(
        roomId: 'ops',
        defaultEffect: AccessEffect.allow,
        entries: const [],
      ).withEntries(const [
        AccessEntry(AccessSubject.authenticated(), AccessPermission.read),
      ]);

      expect(policy.roomId, 'ops');
      expect(policy.defaultEffect, AccessEffect.allow);
      expect(policy.entries, hasLength(1));
      expect(
        () => policy.entries.add(
          const AccessEntry(AccessSubject.everyone(), AccessPermission.read),
        ),
        throwsUnsupportedError,
      );
    });

    test('subjects compare by kind and value', () {
      expect(
        const AccessSubject.email('a'),
        isNot(const AccessSubject.preferredUsername('a')),
      );
      expect(
        const AccessSubject.email('a').hashCode,
        AccessSubject.email(['a'].single).hashCode,
      );
      expect(
        const AccessEntry(AccessSubject.everyone(), AccessPermission.read)
            .hashCode,
        const AccessEntry(AccessSubject.everyone(), AccessPermission.read)
            .hashCode,
      );
      expect(const AccessSubject.email('a').toString(), isNot(contains('a@')));
    });
  });

  group('login checks', () {
    late MockHttpTransport transport;
    late SoliplexApi api;
    final uri = Uri.parse(
      'https://api.example.com/api/v1/installation/jsonpath_functions',
    );

    setUp(() {
      transport = MockHttpTransport();
      when(() => transport.close()).thenReturn(null);
      api = SoliplexApi(
        transport: transport,
        urlBuilder: UrlBuilder('https://api.example.com/api/v1'),
      );
    });

    tearDown(() => api.close());

    void answer(Object? body) => when(
          () => transport.request<Object?>(
            'GET',
            uri,
            cancelToken: any(named: 'cancelToken'),
          ),
        ).thenAnswer((_) async => body);

    test('reads names and descriptions, in order', () async {
      answer([
        {'name': 'has_badge', 'description': null},
        {'name': 'is_staff', 'description': '  Match staff.  ', 'new': 1},
        {'name': 'blank', 'description': ' '},
        {'name': 'bare'},
      ]);

      expect(await api.getLoginChecks(), const [
        LoginCheck('has_badge'),
        LoginCheck('is_staff', description: 'Match staff.'),
        LoginCheck('blank'),
        LoginCheck('bare'),
      ]);
    });

    test('refuses an answer that is not a list of checks', () async {
      const fine = {'name': 'ok'};
      for (final (body, message) in <(Object?, String)>[
        ({'name': 'x'}, 'login checks response is a _Map'),
        (['x'], 'login check 0 is not an object'),
        (
          [fine, <String, dynamic>{}],
          'login check 1 JSON missing required "name" field',
        ),
        (
          [
            fine,
            fine,
            {'name': 'x', 'description': 3},
          ],
          'login check 2 description is not a string',
        ),
      ]) {
        answer(body);
        await expectLater(
          api.getLoginChecks(),
          throwsA(
            isA<MalformedResponseException>().having(
              (e) => e.message,
              'message',
              startsWith(message),
            ),
          ),
          reason: '$body',
        );
      }
    });

    test('a check compares by name and description', () {
      const check = LoginCheck('is_staff', description: 'd');
      expect(check, const LoginCheck('is_staff', description: 'd'));
      expect(check, isNot(const LoginCheck('is_staff')));
      expect(
        check.hashCode,
        const LoginCheck('is_staff', description: 'd').hashCode,
      );
      expect(check.toString(), 'LoginCheck(is_staff)');
    });
  });
}
