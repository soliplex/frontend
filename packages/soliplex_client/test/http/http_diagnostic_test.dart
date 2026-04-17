import 'dart:async';

import 'package:soliplex_client/src/http/http_diagnostic.dart';
import 'package:test/test.dart';

void main() {
  group('safeDiagnosticHandler', () {
    test('passes arguments through to the wrapped handler when it succeeds',
        () {
      Object? capturedError;
      StackTrace? capturedStack;
      String? capturedMessage;
      void inner(
        Object error,
        StackTrace stackTrace, {
        required String message,
      }) {
        capturedError = error;
        capturedStack = stackTrace;
        capturedMessage = message;
      }

      final safe = safeDiagnosticHandler(inner);
      final error = StateError('the original error');
      final stack = StackTrace.current;

      safe(error, stack, message: 'context');

      expect(capturedError, same(error));
      expect(capturedStack, same(stack));
      expect(capturedMessage, 'context');
    });

    test(
        'does not propagate when the wrapped handler throws synchronously — '
        'the caller continues as if nothing happened', () {
      void throwing(Object _, StackTrace __, {required String message}) {
        throw StateError('broken sink');
      }

      final safe = safeDiagnosticHandler(throwing);

      // If the wrapper re-threw, this expression would throw.
      expect(
        () => safe(
          StateError('anything'),
          StackTrace.current,
          message: 'ctx',
        ),
        returnsNormally,
        reason: 'Diagnostic handlers are the last line of defense. A throwing '
            'sink must not break the decorator contract that internal '
            'errors are contained.',
      );
    });

    test(
        'does not propagate when the wrapped handler initiates a '
        'fire-and-forget async error', () async {
      void asyncThrowing(Object _, StackTrace __, {required String message}) {
        // Simulates a Sentry-style sink that schedules work and drops the
        // error future — runZonedGuarded must catch this too.
        unawaited(Future<void>.error(StateError('async sink failure')));
      }

      final safe = safeDiagnosticHandler(asyncThrowing);

      await runZonedGuarded(() async {
        safe(
          StateError('anything'),
          StackTrace.current,
          message: 'ctx',
        );
        // Give the microtask a chance to run. If the wrapper failed to
        // contain the async error, it would surface in this outer zone.
        await Future<void>.delayed(Duration.zero);
      }, (error, stack) {
        fail(
          'Async error from a misbehaving diagnostic handler leaked '
          'into the caller zone: $error',
        );
      });
    });
  });
}
