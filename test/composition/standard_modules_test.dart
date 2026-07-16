import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart'; // AppIdentity
import 'package:soliplex_frontend/src/composition/standard_modules.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/room/room_module.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const secureStorage =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async {
      if (call.method == 'readAll') return <String, String>{};
      return null; // read / write / delete / containsKey / deleteAll
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            null);
  });

  test('buildStandardModules returns the coherent standard set', () async {
    final standardModules =
        await buildStandardModules(identity: AppIdentity.soliplex);

    final namespaces = standardModules.modules.map((m) => m.namespace).toList();
    expect(namespaces.toSet().length, namespaces.length,
        reason: 'module namespaces are unique');
    expect(standardModules.modules.length, 6);
    expect(standardModules.initialRoute, AppRoutes.home);
  });

  test('initialRoute is the auth callback when callback params are present',
      () async {
    final standardModules = await buildStandardModules(
      identity: AppIdentity.soliplex,
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
    );

    expect(standardModules.initialRoute, AppRoutes.authCallback);
  });

  test('enableDocumentFilter is forwarded to the room module', () async {
    final off = await buildStandardModules(
      identity: AppIdentity.soliplex,
      enableDocumentFilter: false,
    );
    final on = await buildStandardModules(identity: AppIdentity.soliplex);

    expect(
      off.modules.whereType<RoomAppModule>().single.enableDocumentFilter,
      isFalse,
    );
    expect(
      on.modules.whereType<RoomAppModule>().single.enableDocumentFilter,
      isTrue,
    );
  });
}
