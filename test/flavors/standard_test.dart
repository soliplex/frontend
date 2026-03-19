import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:soliplex_frontend/flavors.dart';
import 'package:soliplex_frontend/soliplex_frontend.dart';

import '../helpers/fakes.dart';

void main() {
  group('standard()', () {
    late ShellConfig config;

    setUp(() async {
      config = await standard(storage: InMemoryTokenStorage());
    });

    tearDown(() {
      config.onDispose?.call();
    });

    test('includes a root route', () {
      final paths = config.routes.whereType<GoRoute>().map((r) => r.path);
      expect(paths, contains('/'));
    });

    test('initial auth state is Unauthenticated', () {
      final container = ProviderContainer(overrides: config.overrides);
      addTearDown(container.dispose);

      final manager = container.read(serverManagerProvider);
      expect(manager.authState.value, isA<Unauthenticated>());
    });
  });
}
