// Deliberately imports the barrel and NOTHING from package:go_router. A module
// author outside this package has no go_router dependency of their own, so if a
// symbol they need is missing from the barrel's `show` clause this file stops
// compiling — which is the only way this repo can assert that the extension
// point is usable as shipped.
//
// Authoring and *testing* a module are separate demands on that clause:
// declaring routes needs GoRoute and friends, while driving one needs a real
// GoRouter above the widget. Both are exercised below, because a consumer who
// can write a module but not test it has half an extension point.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

class _WelcomeModule extends AppModule {
  static const path = '/welcome';

  @override
  String get namespace => 'welcome';

  @override
  ModuleRoutes build() => ModuleRoutes(
        // RouteBase, GoRoute and GoRouterState all come from the barrel.
        routes: <RouteBase>[
          GoRoute(
            path: path,
            builder: (context, GoRouterState state) => _Welcome(
              query: state.uri.queryParameters['ref'],
            ),
          ),
          GoRoute(
            path: '/connected',
            builder: (_, __) => const Text('connected'),
          ),
        ],
        publicPaths: const {path},
      );
}

class _Welcome extends StatelessWidget {
  const _Welcome({this.query});

  final String? query;

  @override
  Widget build(BuildContext context) => TextButton(
        // GoRouterHelper: an extension on BuildContext. Dart's `show` gates
        // extensions, so this line is what proves it is named in the clause.
        onPressed: () => context.go('/connected'),
        child: Text('continue ${query ?? ''}'),
      );
}

void main() {
  testWidgets('a module can be authored and driven against the barrel alone',
      (tester) async {
    // buildRouter and GoRouter both come from the barrel. Going through
    // ShellConfig rather than hand-assembling a GoRouter is the point: it is
    // the composition the shell itself runs, so a consumer's test cannot drift
    // from production by reproducing it slightly differently.
    final config = ShellConfig.fromModules(
      modules: [_WelcomeModule()],
      appName: 'Test',
      lightTheme: buildSoliplexThemeData(
        colors: lightSoliplexColors,
        brightness: Brightness.light,
      ),
      initialRoute: _WelcomeModule.path,
    );
    final GoRouter router = buildRouter(config);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();

    expect(find.byType(TextButton), findsOneWidget);

    await tester.tap(find.byType(TextButton));
    await tester.pumpAndSettle();

    expect(find.text('connected'), findsOneWidget);
  });
}
