import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/core/inactivity/inactivity_provider.dart';

void main() {
  group('inactivityMonitorProvider', () {
    test('is null when the auth-module providers are not overridden', () {
      // Their defaults throw UnimplementedError; the shell stays bootable
      // with inactivity logout disabled.
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(inactivityMonitorProvider), isNull);
    });
  });
}
