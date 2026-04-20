import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';

final _baseTime = DateTime.utc(2026, 3, 19, 12, 0);

PreAuthState _makeState({DateTime? createdAt}) => PreAuthState(
  serverUrl: Uri.parse('https://api.example.com'),
  providerId: 'keycloak',
  discoveryUrl: 'https://sso.example.com/.well-known/openid-configuration',
  clientId: 'soliplex',
  createdAt: createdAt ?? _baseTime,
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

    test('isExpired returns false within maxAge', () {
      final state = _makeState();
      final now = _baseTime.add(const Duration(minutes: 4, seconds: 59));

      expect(state.isExpired(now: now), isFalse);
    });

    test('isExpired returns true after maxAge', () {
      final state = _makeState();
      final now = _baseTime.add(const Duration(minutes: 5, seconds: 1));

      expect(state.isExpired(now: now), isTrue);
    });

    test('equality', () {
      final a = _makeState();
      final b = _makeState();

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('PreAuthStateStorage', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('save and load round-trip', () async {
      final state = _makeState();

      await PreAuthStateStorage.save(state);
      final loaded = await PreAuthStateStorage.load(now: _baseTime);

      expect(loaded, isNotNull);
      expect(loaded!.serverUrl, state.serverUrl);
      expect(loaded.providerId, state.providerId);
      expect(loaded.discoveryUrl, state.discoveryUrl);
      expect(loaded.clientId, state.clientId);
    });

    test('load returns null when nothing saved', () async {
      final loaded = await PreAuthStateStorage.load();
      expect(loaded, isNull);
    });

    test('load returns null and clears expired state', () async {
      final state = _makeState();
      await PreAuthStateStorage.save(state);

      final expiredNow = _baseTime.add(const Duration(minutes: 6));
      final loaded = await PreAuthStateStorage.load(now: expiredNow);
      expect(loaded, isNull);

      // Verify storage was cleaned up.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(PreAuthStateStorage.storageKey), isNull);
    });

    test('clear removes stored state', () async {
      final state = _makeState();
      await PreAuthStateStorage.save(state);
      await PreAuthStateStorage.clear();

      final loaded = await PreAuthStateStorage.load(now: _baseTime);
      expect(loaded, isNull);
    });

    test('load returns null and clears corrupted data', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PreAuthStateStorage.storageKey, 'not json');

      final loaded = await PreAuthStateStorage.load();
      expect(loaded, isNull);

      // Verify storage was cleaned up.
      expect(prefs.getString(PreAuthStateStorage.storageKey), isNull);
    });
  });
}
