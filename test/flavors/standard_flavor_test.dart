import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';

import 'platform_mocks.dart';

class _ExtraModule extends AppModule {
  @override
  String get namespace => 'extra';

  @override
  ModuleRoutes build() => const ModuleRoutes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  installPlatformMocks();

  test('maps the kit onto the Flavor and appends extra modules last', () async {
    StandardKit? captured;
    final extra = _ExtraModule();

    final flavor = await standardFlavor(
      // Callback params drive the kit's initialRoute off the '/' default, so
      // a dropped kit-to-Flavor mapping can't hide behind matching defaults.
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
      extraModules: (kit) {
        captured = kit;
        return [extra];
      },
    );

    final kit = captured!;
    expect(flavor.identity.appName, 'Soliplex');
    expect(kit.initialRoute, AppRoutes.authCallback);
    expect(flavor.initialRoute, kit.initialRoute);
    expect(flavor.refreshListenable, same(kit.refreshListenable));
    expect(flavor.inactivity, same(kit.inactivity));
    expect(flavor.modules.sublist(0, kit.modules.length), kit.modules);
    expect(flavor.modules.last, same(extra));
  });
}
