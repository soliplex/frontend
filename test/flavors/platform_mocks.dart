import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _secureStorage =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

/// Registers `setUp`/`tearDown` hooks mocking the platform channels the
/// standard kit touches during provisioning (SharedPreferences and secure
/// storage), so `buildStandardKit` can run in a test environment.
void installPlatformMocks() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null; // read / write / delete / containsKey / deleteAll
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorage, null);
  });
}

/// Overrides the secure-storage `readAll` handler to return [entries], so a
/// test can provision `buildStandardKit` with persisted servers. Call inside
/// the test body — it supersedes the empty handler [installPlatformMocks] sets.
void seedSecureStorage(Map<String, String> entries) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_secureStorage, (call) async {
    if (call.method == 'readAll') return entries;
    return null;
  });
}
