import 'package:dart_monty/dart_monty_bridge.dart'
    show OsCallHandler, OsCallPermissionError;
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/access_policy.dart';
import 'package:soliplex_frontend/src/modules/room/policy_os_call_handler.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a simple [OsCallHandler] that records calls and returns a result.
OsCallHandler _trackingInner(List<String> calls) {
  return (op, args, kwargs) async {
    calls.add(op);
    return 'result:$op';
  };
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('PolicyOsCallHandler', () {
    group('permissive policy', () {
      test('passes all ops through to inner handler', () async {
        final calls = <String>[];
        final ph = PolicyOsCallHandler(inner: _trackingInner(calls));

        final r1 = await ph.handler('Path.read_text', [], null);
        final r2 = await ph.handler('Path.write_text', [], null);
        final r3 = await ph.handler('os.getenv', [], null);

        expect(r1, 'result:Path.read_text');
        expect(r2, 'result:Path.write_text');
        expect(r3, 'result:os.getenv');
        expect(calls, ['Path.read_text', 'Path.write_text', 'os.getenv']);
      });
    });

    group('readOnly policy', () {
      test('allows read ops', () async {
        final calls = <String>[];
        final ph = PolicyOsCallHandler(
          inner: _trackingInner(calls),
          policy: const AccessPolicy(osFilter: OsFilter.readOnly),
        );

        await ph.handler('Path.read_text', [], null);
        await ph.handler('Path.exists', [], null);
        expect(calls, ['Path.read_text', 'Path.exists']);
      });

      test('throws OsCallPermissionError for write ops', () async {
        final ph = PolicyOsCallHandler(
          inner: _trackingInner([]),
          policy: const AccessPolicy(osFilter: OsFilter.readOnly),
        );

        await expectLater(
          () => ph.handler('Path.write_text', [], null),
          throwsA(
            isA<OsCallPermissionError>().having(
              (e) => e.operation,
              'operation',
              'Path.write_text',
            ),
          ),
        );
      });

      test('blocks all OsFilter.readOnly denied ops', () async {
        final writeOps = [
          'Path.write_text',
          'Path.write_bytes',
          'Path.mkdir',
          'Path.unlink',
          'Path.rmdir',
          'Path.rename',
        ];
        final ph = PolicyOsCallHandler(
          inner: _trackingInner([]),
          policy: const AccessPolicy(osFilter: OsFilter.readOnly),
        );

        for (final op in writeOps) {
          await expectLater(
            () => ph.handler(op, [], null),
            throwsA(isA<OsCallPermissionError>()),
            reason: '$op should be denied',
          );
        }
      });

      test('inner handler never called for denied ops', () async {
        final calls = <String>[];
        final ph = PolicyOsCallHandler(
          inner: _trackingInner(calls),
          policy: const AccessPolicy(osFilter: OsFilter.readOnly),
        );

        try {
          await ph.handler('Path.write_text', [], null);
        } on OsCallPermissionError {
          // expected
        }

        expect(calls, isEmpty);
      });
    });

    group('custom denied ops', () {
      test('blocks custom denied op', () async {
        final ph = PolicyOsCallHandler(
          inner: _trackingInner([]),
          policy: const AccessPolicy(
            osFilter: OsFilter(deniedOps: {'os.getenv'}),
          ),
        );

        await expectLater(
          () => ph.handler('os.getenv', [], null),
          throwsA(isA<OsCallPermissionError>()),
        );
      });

      test('allows ops not in denied set', () async {
        final calls = <String>[];
        final ph = PolicyOsCallHandler(
          inner: _trackingInner(calls),
          policy: const AccessPolicy(
            osFilter: OsFilter(deniedOps: {'os.getenv'}),
          ),
        );

        await ph.handler('Path.read_text', [], null);
        expect(calls, ['Path.read_text']);
      });
    });

    group('policy setter', () {
      test('updating policy takes effect immediately', () async {
        final calls = <String>[];
        final ph = PolicyOsCallHandler(inner: _trackingInner(calls));

        // Permissive — write allowed
        await ph.handler('Path.write_text', [], null);
        expect(calls, ['Path.write_text']);

        // Tighten to readOnly
        ph.policy = const AccessPolicy(osFilter: OsFilter.readOnly);

        await expectLater(
          () => ph.handler('Path.write_text', [], null),
          throwsA(isA<OsCallPermissionError>()),
        );
        expect(calls.length, 1); // no extra call
      });
    });

    group('handler getter', () {
      test('returns a callable OsCallHandler', () {
        final ph = PolicyOsCallHandler(inner: _trackingInner([]));
        final handler = ph.handler;
        expect(handler, isA<OsCallHandler>());
      });
    });
  });
}
