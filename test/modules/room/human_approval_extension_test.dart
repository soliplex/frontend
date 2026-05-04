import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/human_approval_extension.dart';

class _MockAgentSession extends Mock implements AgentSession {}

Future<void> _attach(HumanApprovalExtension ext, CancelToken token) {
  final session = _MockAgentSession();
  when(() => session.cancelToken).thenReturn(token);
  return ext.onAttach(session);
}

void main() {
  group('ApprovalRequest equality', () {
    test('equal when all fields equal (including arguments)', () {
      final a = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {'to': 'a@b.c', 'body': 'hi'},
        rationale: 'send email to user',
      );
      final b = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {'to': 'a@b.c', 'body': 'hi'},
        rationale: 'send email to user',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when arguments differ at top level', () {
      final a = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {'to': 'a@b.c'},
        rationale: 'rationale',
      );
      final b = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {'to': 'x@y.z'},
        rationale: 'rationale',
      );
      expect(a, isNot(equals(b)));
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('not equal when arguments differ in a nested map', () {
      final a = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {
          'meta': {'priority': 1},
        },
        rationale: 'r',
      );
      final b = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {
          'meta': {'priority': 2},
        },
        rationale: 'r',
      );
      expect(a, isNot(equals(b)));
    });

    test('equal when arguments are structurally equal nested maps', () {
      final a = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {
          'meta': {
            'priority': 1,
            'tags': ['x', 'y']
          },
        },
        rationale: 'r',
      );
      final b = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {
          'meta': {
            'priority': 1,
            'tags': ['x', 'y']
          },
        },
        rationale: 'r',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('not equal when toolCallId differs', () {
      final a = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 'x',
        arguments: const {},
        rationale: 'r',
      );
      final b = ApprovalRequest(
        toolCallId: 'tc-2',
        toolName: 'x',
        arguments: const {},
        rationale: 'r',
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('HumanApprovalExtension', () {
    late HumanApprovalExtension ext;

    setUp(() {
      ext = HumanApprovalExtension();
    });

    test('initial state is null', () {
      expect(ext.stateSignal.value, isNull);
    });

    test('requestApproval sets state and returns pending future', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 'send_email',
        arguments: const {'to': 'a@b.c'},
        rationale: 'send a message',
      );

      final pending = ext.stateSignal.value;
      expect(pending, isNotNull);
      expect(pending!.toolCallId, 'tc-1');
      expect(pending.toolName, 'send_email');
      expect(pending.arguments, equals({'to': 'a@b.c'}));
      expect(pending.rationale, 'send a message');

      var resolved = false;
      // ignore: unawaited_futures
      future.then((_) => resolved = true);
      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse);

      ext.respond(pending, true);
      expect(await future, isTrue);
    });

    test('respond(true) resolves and clears state', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      ext.respond(ext.stateSignal.value!, true);
      expect(await future, isTrue);
      expect(ext.stateSignal.value, isNull);
    });

    test('respond(false) resolves and clears state', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      ext.respond(ext.stateSignal.value!, false);
      expect(await future, isFalse);
      expect(ext.stateSignal.value, isNull);
    });

    test('respond with no pending is a silent no-op', () {
      final stale = ApprovalRequest(
        toolCallId: 'tc-x',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      expect(() => ext.respond(stale, true), returnsNormally);
      expect(ext.stateSignal.value, isNull);
    });

    test('respond with non-current request is a silent no-op', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      final current = ext.stateSignal.value!;

      // A different request instance with the same fields must NOT resolve
      // the current pending — identity is the key.
      final stale = ApprovalRequest(
        toolCallId: 'tc-1',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      ext.respond(stale, true);
      expect(ext.stateSignal.value, equals(current));

      var resolved = false;
      // ignore: unawaited_futures
      future.then((_) => resolved = true);
      await Future<void>.delayed(Duration.zero);
      expect(resolved, isFalse);

      ext.respond(current, false);
      expect(await future, isFalse);
    });

    test('second requestApproval auto-denies the first and replaces state',
        () async {
      final firstFuture = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 't1',
        arguments: const {},
        rationale: 'r1',
      );
      final secondFuture = ext.requestApproval(
        toolCallId: 'tc-2',
        toolName: 't2',
        arguments: const {},
        rationale: 'r2',
      );

      expect(await firstFuture, isFalse);
      expect(ext.stateSignal.value!.toolCallId, 'tc-2');

      ext.respond(ext.stateSignal.value!, true);
      expect(await secondFuture, isTrue);
      expect(ext.stateSignal.value, isNull);
    });

    test('onDispose denies pending and clears state', () async {
      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      ext.onDispose();
      expect(await future, isFalse);
    });

    test(
      'cancel via attached cancelToken denies pending and clears state',
      () async {
        final token = CancelToken();
        await _attach(ext, token);

        final future = ext.requestApproval(
          toolCallId: 'tc-1',
          toolName: 't',
          arguments: const {},
          rationale: 'r',
        );
        expect(ext.stateSignal.value, isNotNull);

        token.cancel('test');
        expect(await future, isFalse);
        expect(ext.stateSignal.value, isNull);
      },
    );

    test('respond after cancel-already-denied is a silent no-op', () async {
      final token = CancelToken();
      await _attach(ext, token);

      final future = ext.requestApproval(
        toolCallId: 'tc-1',
        toolName: 't',
        arguments: const {},
        rationale: 'r',
      );
      final pending = ext.stateSignal.value!;
      token.cancel();
      expect(await future, isFalse);

      // No StateError on subsequent respond against the same request.
      expect(() => ext.respond(pending, true), returnsNormally);
    });
  });
}
