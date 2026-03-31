import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  group('NativePlatformConstraints', () {
    test('supports parallel execution', () {
      const constraints = NativePlatformConstraints();
      expect(constraints.supportsParallelExecution, isTrue);
    });

    test('does not support async mode', () {
      const constraints = NativePlatformConstraints();
      expect(constraints.supportsAsyncMode, isFalse);
    });

    test('defaults to 4 max concurrent bridges', () {
      const constraints = NativePlatformConstraints();
      expect(constraints.maxConcurrentBridges, equals(4));
    });

    test('accepts custom max concurrent bridges', () {
      const constraints = NativePlatformConstraints(maxConcurrentBridges: 8);
      expect(constraints.maxConcurrentBridges, equals(8));
    });

    test('supports reentrant interpreter', () {
      const constraints = NativePlatformConstraints();
      expect(constraints.supportsReentrantInterpreter, isTrue);
    });

    test('maxConcurrentSessions matches maxConcurrentBridges', () {
      const constraints = NativePlatformConstraints();
      expect(constraints.maxConcurrentSessions, equals(4));
    });

    test('custom bridges reflects in sessions', () {
      const constraints = NativePlatformConstraints(maxConcurrentBridges: 8);
      expect(constraints.maxConcurrentSessions, equals(8));
    });

    test('implements PlatformConstraints', () {
      const PlatformConstraints constraints = NativePlatformConstraints();
      expect(constraints, isA<PlatformConstraints>());
    });
  });

  group('WebPlatformConstraints', () {
    test('does not support parallel execution', () {
      const constraints = WebPlatformConstraints();
      expect(constraints.supportsParallelExecution, isFalse);
    });

    test('does not support async mode', () {
      const constraints = WebPlatformConstraints();
      expect(constraints.supportsAsyncMode, isFalse);
    });

    test('allows only 1 concurrent bridge', () {
      const constraints = WebPlatformConstraints();
      expect(constraints.maxConcurrentBridges, equals(1));
    });

    test('does not support reentrant interpreter', () {
      const constraints = WebPlatformConstraints();
      expect(constraints.supportsReentrantInterpreter, isFalse);
    });

    test('defaults to 4 max concurrent sessions', () {
      const constraints = WebPlatformConstraints();
      expect(constraints.maxConcurrentSessions, equals(4));
    });

    test('accepts custom max concurrent sessions', () {
      const constraints = WebPlatformConstraints(maxConcurrentSessions: 8);
      expect(constraints.maxConcurrentSessions, equals(8));
    });

    test('implements PlatformConstraints', () {
      const PlatformConstraints constraints = WebPlatformConstraints();
      expect(constraints, isA<PlatformConstraints>());
    });
  });

  group('MobilePlatformConstraints', () {
    test('supports parallel execution', () {
      const constraints = MobilePlatformConstraints();
      expect(constraints.supportsParallelExecution, isTrue);
    });

    test('defaults to 2 max concurrent bridges', () {
      const constraints = MobilePlatformConstraints();
      expect(constraints.maxConcurrentBridges, equals(2));
    });

    test('accepts custom max concurrent bridges', () {
      const constraints = MobilePlatformConstraints(maxConcurrentBridges: 3);
      expect(constraints.maxConcurrentBridges, equals(3));
    });

    test('supports reentrant interpreter', () {
      const constraints = MobilePlatformConstraints();
      expect(constraints.supportsReentrantInterpreter, isTrue);
    });

    test('maxConcurrentSessions matches maxConcurrentBridges', () {
      const constraints = MobilePlatformConstraints();
      expect(constraints.maxConcurrentSessions, equals(2));
    });

    test('implements PlatformConstraints', () {
      const PlatformConstraints constraints = MobilePlatformConstraints();
      expect(constraints, isA<PlatformConstraints>());
    });
  });

  group('PlatformConstraints interface', () {
    test('native and web have opposite parallel support', () {
      const native = NativePlatformConstraints();
      const web = WebPlatformConstraints();

      expect(
        native.supportsParallelExecution,
        isNot(web.supportsParallelExecution),
      );
    });

    test('native and web have opposite reentrant support', () {
      const native = NativePlatformConstraints();
      const web = WebPlatformConstraints();

      expect(
        native.supportsReentrantInterpreter,
        isNot(web.supportsReentrantInterpreter),
      );
    });
  });
}
