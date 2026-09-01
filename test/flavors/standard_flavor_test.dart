import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';
import 'package:soliplex_frontend/src/core/routes.dart';
import 'package:soliplex_frontend/src/modules/auth/platform/callback_params.dart';
import 'package:soliplex_frontend/src/modules/room/document_browser_url.dart';

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

  test('a flavor module can serve its own route without a session', () async {
    // This is the whole feature: the module that registers the route is the
    // one that declares it needs no session.
    final flavor = await standardFlavor(
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
      extraModules: (_) => [_WelcomeModule()],
    );

    expect(flavor.build().publicPaths, contains(_WelcomeModule.path));
  });

  test('the standard flavor serves exactly these paths without a session',
      () async {
    // The security surface, pinned whole rather than per module: a module that
    // opens one of its own routes widens this set and nothing else in the suite
    // notices. Adding a path here is a deliberate act and should read as one in
    // review.
    final flavor = await standardFlavor(
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
    );

    expect(flavor.build().publicPaths, {
      AppRoutes.home,
      AppRoutes.authCallback,
      AppRoutes.versions,
      AppRoutes.diagnostics,
    });
  });

  test('the sign-in guard is the only global redirect', () async {
    final flavor = await standardFlavor(
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
    );

    expect(
      flavor.build().redirects,
      hasLength(1),
      reason: 'A declared public path short-circuits the whole redirect loop '
          'in buildRouter, not just the sign-in guard. So a second global '
          'redirect added here is silently skipped for "/", "/auth/callback", '
          '"/versions" and "/diagnostics" — paths three other modules declare, '
          'and none of them can be un-declared. Before adding one, give it an '
          'exemption list of its own rather than inheriting publicPaths, which '
          'is the sign-in guard\'s.',
    );
  });

  test('signedOutLandingPath reaches the flavor', () async {
    // Unlike its neighbours this passes no callbackParams: a callback wins the
    // initialRoute outright, so the signed-out branch would never be reached.
    final flavor = await standardFlavor(
      signedOutLandingPath: '/welcome',
    );

    expect(flavor.initialRoute, '/welcome');
  });

  test('documentBrowserUrl installs the resolver override', () async {
    Uri? resolver(String uri) => Uri.parse('https://example.test/x');

    final flavor = await standardFlavor(
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
      documentBrowserUrl: resolver,
    );
    final container = ProviderContainer(overrides: flavor.build().overrides);
    addTearDown(container.dispose);

    expect(container.read(documentBrowserUrlResolverProvider), same(resolver));
  });

  test('no documentBrowserUrl leaves the resolver returning null', () async {
    final flavor = await standardFlavor(
      callbackParams: WebCallbackSuccess(accessToken: 'x'),
    );
    final container = ProviderContainer(overrides: flavor.build().overrides);
    addTearDown(container.dispose);

    expect(
      container.read(documentBrowserUrlResolverProvider)('file:///x/a.pdf'),
      isNull,
    );
  });
}

class _WelcomeModule extends AppModule {
  static const path = '/welcome';

  @override
  String get namespace => 'welcome';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [GoRoute(path: path, builder: (_, __) => const SizedBox())],
        publicPaths: const {path},
      );
}
