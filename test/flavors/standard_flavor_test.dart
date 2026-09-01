import 'package:flutter/material.dart';
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

  testWidgets('an unauthenticated visitor reaches a flavor route and no other',
      (tester) async {
    // The whole feature, driven rather than described: the module that
    // registers the route declares it needs no session, and the real sign-in
    // guard then lets it through while still bouncing everything else. No
    // server is connected, so every navigation below is made signed out.
    final flavor = await standardFlavor(
      extraModules: (_) => [_WelcomeModule(), _GuardedModule()],
    );
    final config = flavor.build();
    addTearDown(config.dispose);

    final router = buildRouter(config);
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: config.overrides,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    String at() => router.routerDelegate.currentConfiguration.uri.path;

    router.go(_WelcomeModule.path);
    await tester.pumpAndSettle();
    expect(at(), _WelcomeModule.path, reason: 'declared: must not redirect');

    router.go(_GuardedModule.path);
    await tester.pumpAndSettle();
    expect(at(), AppRoutes.home, reason: 'not declared: must still redirect');
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

  test('a signed-out launch starts on the declared landing path', () async {
    // Unlike its neighbours this passes no callbackParams: a callback wins the
    // initialRoute outright, so the signed-out branch would never be reached.
    // It builds, rather than reading the field, because a landing path that
    // reaches initialRoute but fails validation is not a working feature.
    final flavor = await standardFlavor(
      signedOutLandingPath: _WelcomeModule.path,
      extraModules: (_) => [_WelcomeModule()],
    );

    expect(flavor.initialRoute, _WelcomeModule.path);
    expect(flavor.build().initialRoute, _WelcomeModule.path);
  });

  test('a landing path no module declared public is refused at build',
      () async {
    // The guard would bounce a signed-out launch straight off it. Nothing
    // about that depends on being signed out, so it fails here rather than
    // waiting for the launch that would have shown it.
    final flavor = await standardFlavor(
      signedOutLandingPath: _GuardedModule.path,
      extraModules: (_) => [_GuardedModule()],
    );

    expect(
      flavor.build,
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('not declared reachable without a session'),
        ),
      ),
    );
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

/// Registers a route but declares nothing public, so naming it as the landing
/// path is the mistake the build must refuse.
class _GuardedModule extends AppModule {
  static const path = '/members';

  @override
  String get namespace => 'guarded';

  @override
  ModuleRoutes build() => ModuleRoutes(
        routes: [GoRoute(path: path, builder: (_, __) => const SizedBox())],
      );
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
