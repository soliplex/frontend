import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/auth/pre_auth_state.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

// A file of its own: `SharedPreferences.setMockInitialValues` replaces the
// platform store with one that never fails, for the rest of the isolate, so
// these tests reach the platform channel only where nothing has called it.
const _channel = MethodChannel('plugins.flutter.io/shared_preferences');

/// Answers the platform store's calls with [handler], until the test ends.
void _platformStore(Future<Object?> Function(MethodCall call) handler) {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_channel, handler);
  addTearDown(() {
    messenger.setMockMethodCallHandler(_channel, null);
    SharedPreferences.resetStatic();
  });
}

/// The store holding [raw] under the pre-auth key, whose `remove` fails.
/// Every other call fails with a different code, so a test can tell the
/// failed clear from a read that never happened.
Future<Object?> _storeWithFailingRemove(MethodCall call, String raw) async =>
    switch (call.method) {
      'getAll' => {'flutter.${LocalPreAuthStateStorage.storageKey}': raw},
      'remove' => throw PlatformException(code: 'remove failed'),
      _ => throw PlatformException(code: 'unexpected call'),
    };

MemorySink _captureLogs() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return sink;
}

/// The single pre-auth-state warning in [sink] with [message].
LogRecord _warning(MemorySink sink, String message) => sink.records
    .where((r) =>
        r.loggerName == 'soliplex.pre_auth_state' &&
        r.level == LogLevel.warning &&
        r.message == message)
    .single;

Matcher get _failedRemove =>
    isA<PlatformException>().having((e) => e.code, 'code', 'remove failed');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LocalPreAuthStateStorage.load when storage fails', () {
    test('returns null when the store cannot be read', () async {
      _platformStore((_) async => throw PlatformException(code: 'unavailable'));

      expect(await const LocalPreAuthStateStorage().load(), isNull);
    });

    test('returns null when an expired state cannot be cleared', () async {
      final createdAt = DateTime.utc(2026, 3, 19, 12);
      final state = PreAuthState(
        serverUrl: Uri.parse('https://api.example.com'),
        providerId: 'keycloak',
        discoveryUrl:
            'https://sso.example.com/.well-known/openid-configuration',
        clientId: 'soliplex',
        createdAt: createdAt,
      );
      final sink = _captureLogs();
      _platformStore(
        (call) => _storeWithFailingRemove(call, jsonEncode(state.toJson())),
      );

      final loaded = await const LocalPreAuthStateStorage()
          .load(now: createdAt.add(const Duration(minutes: 31)));

      expect(loaded, isNull);
      expect(
        _warning(sink, 'Failed to clear the pre-auth state').error,
        _failedRemove,
      );
    });

    test('returns null when unreadable data cannot be cleared', () async {
      final sink = _captureLogs();
      _platformStore((call) => _storeWithFailingRemove(call, 'not json'));

      expect(await const LocalPreAuthStateStorage().load(), isNull);
      expect(
        _warning(sink, 'Failed to load pre-auth state').attributes['failure'],
        startsWith('FormatException'),
      );
      expect(
        _warning(sink, 'Failed to clear the pre-auth state').error,
        _failedRemove,
      );
    });
  });
}
