import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';

final _baseTime = DateTime.utc(2026, 3, 19, 12, 0);

PreAuthState _makeState({
  DateTime? createdAt,
  String? frontendReturnTo,
  String? serverName,
  String? serverDescription,
}) =>
    PreAuthState(
      serverUrl: Uri.parse('https://api.example.com'),
      providerId: 'keycloak',
      discoveryUrl: 'https://sso.example.com/.well-known/openid-configuration',
      clientId: 'soliplex',
      createdAt: createdAt ?? _baseTime,
      frontendReturnTo: frontendReturnTo,
      serverName: serverName,
      serverDescription: serverDescription,
    );

void main() {
  group('PreAuthState', () {
    test('JSON serialization round-trip', () {
      final state = _makeState();

      final json = state.toJson();
      final restored = PreAuthState.fromJson(json);

      expect(restored.serverUrl, state.serverUrl);
      expect(restored.providerId, state.providerId);
      expect(restored.discoveryUrl, state.discoveryUrl);
      expect(restored.clientId, state.clientId);
      expect(restored.createdAt, state.createdAt);
    });

    test('createdAt is stored and restored as UTC', () {
      final state = _makeState();
      final json = state.toJson();
      final restored = PreAuthState.fromJson(json);

      expect(restored.createdAt.isUtc, isTrue);
    });

    test('isExpired returns false within 30-minute maxAge', () {
      // 30 minutes covers typical OIDC roundtrips that involve a
      // password reset, MFA prompt, or email magic link.
      final state = _makeState();
      final now = _baseTime.add(const Duration(minutes: 29, seconds: 59));

      expect(state.isExpired(now: now), isFalse);
    });

    test('isExpired returns true after 30-minute maxAge', () {
      final state = _makeState();
      final now = _baseTime.add(const Duration(minutes: 30, seconds: 1));

      expect(state.isExpired(now: now), isTrue);
    });

    test('server name and description round-trip through JSON', () {
      final state = _makeState(
        serverName: 'Demo Server',
        serverDescription: 'A friendly demo instance',
      );

      final restored = PreAuthState.fromJson(state.toJson());

      expect(restored.serverName, 'Demo Server');
      expect(restored.serverDescription, 'A friendly demo instance');
      expect(restored, equals(state));
    });

    test('omits server name/description from JSON when null', () {
      final json = _makeState().toJson();

      expect(json.containsKey('serverName'), isFalse);
      expect(json.containsKey('serverDescription'), isFalse);
    });

    test('frontendReturnTo round-trips through JSON', () {
      final state = _makeState(frontendReturnTo: '/room/server-a/r1');

      final restored = PreAuthState.fromJson(state.toJson());

      expect(restored.frontendReturnTo, '/room/server-a/r1');
    });

    test('frontendReturnTo defaults to null and round-trips as null', () {
      final state = _makeState();

      final restored = PreAuthState.fromJson(state.toJson());

      expect(state.frontendReturnTo, isNull);
      expect(restored.frontendReturnTo, isNull);
    });

    test('constructor rejects open-redirect candidates for frontendReturnTo',
        () {
      // The constructor is the type-level open-redirect guard: any
      // value that isn't an in-app path starting with a single `/`
      // must throw before it can be persisted or honored by the
      // callback.
      for (final unsafe in [
        'https://evil.com/x',
        'http://evil.com/x',
        '//evil.com/x',
        'lobby',
        '../admin',
        '',
      ]) {
        expect(
          () => _makeState(frontendReturnTo: unsafe),
          throwsA(isA<ArgumentError>()),
          reason: 'unsafe=$unsafe should be rejected by the constructor',
        );
      }
    });

    test('isSafeReturnTo rejects a path or query that does not decode', () {
      for (final route in ['/room/%FF/x', '/lobby?server=%FF']) {
        expect(isSafeReturnTo(route), isFalse, reason: route);
        expect(
          () => _makeState(frontendReturnTo: route),
          throwsA(isA<ArgumentError>()),
          reason: route,
        );
      }
      expect(isSafeReturnTo('/room/a/b?x=1'), isTrue);
    });

    test('constructor accepts safe relative paths for frontendReturnTo', () {
      for (final safe in [
        '/lobby',
        '/room/server-a/r1',
        '/room/server-a/r1?focus=last',
      ]) {
        expect(
          () => _makeState(frontendReturnTo: safe),
          returnsNormally,
          reason: 'safe=$safe should be accepted',
        );
      }
    });

    test('equality', () {
      final a = _makeState();
      final b = _makeState();

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('LocalPreAuthStateStorage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load round-trip', () async {
      final state = _makeState();

      await const LocalPreAuthStateStorage().save(state);
      final loaded =
          await const LocalPreAuthStateStorage().load(now: _baseTime);

      expect(loaded, isNotNull);
      expect(loaded!.serverUrl, state.serverUrl);
      expect(loaded.providerId, state.providerId);
      expect(loaded.discoveryUrl, state.discoveryUrl);
      expect(loaded.clientId, state.clientId);
    });

    test('load returns null when nothing saved', () async {
      final loaded = await const LocalPreAuthStateStorage().load();
      expect(loaded, isNull);
    });

    test('load returns null and clears expired state', () async {
      final state = _makeState();
      await const LocalPreAuthStateStorage().save(state);

      final expiredNow = _baseTime.add(const Duration(minutes: 31));
      final loaded =
          await const LocalPreAuthStateStorage().load(now: expiredNow);
      expect(loaded, isNull);

      // Verify storage was cleaned up.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(LocalPreAuthStateStorage.storageKey), isNull);
    });

    test('clear removes stored state', () async {
      final state = _makeState();
      await const LocalPreAuthStateStorage().save(state);
      await const LocalPreAuthStateStorage().clear();

      final loaded =
          await const LocalPreAuthStateStorage().load(now: _baseTime);
      expect(loaded, isNull);
    });

    test('a stored return page that does not decode clears the state',
        () async {
      final json = _makeState().toJson()
        ..['frontendReturnTo'] = '/lobby?server=%FF';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          LocalPreAuthStateStorage.storageKey, jsonEncode(json));

      final loaded =
          await const LocalPreAuthStateStorage().load(now: _baseTime);

      expect(loaded, isNull);
      expect(prefs.getString(LocalPreAuthStateStorage.storageKey), isNull);
    });

    test('load returns null and clears corrupted data', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(LocalPreAuthStateStorage.storageKey, 'not json');

      final loaded = await const LocalPreAuthStateStorage().load();
      expect(loaded, isNull);

      // Verify storage was cleaned up.
      expect(prefs.getString(LocalPreAuthStateStorage.storageKey), isNull);
    });
  });
}
