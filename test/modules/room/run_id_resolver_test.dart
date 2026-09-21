import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/run_id_resolver.dart';

TextMessage _assistant(String id, {String? run}) => TextMessage(
      id: id,
      user: ChatUser.assistant,
      createdAt: null,
      text: 'Here.',
      runId: run,
    );

TextMessage _user(String id, {String? run}) => TextMessage(
      id: id,
      user: ChatUser.user,
      createdAt: null,
      text: 'ask',
      runId: run,
    );

MessageState _association(String userMessageId, String runId) => MessageState(
      userMessageId: userMessageId,
      sourceReferences: const [],
      runId: runId,
    );

void main() {
  group('an assistant tile', () {
    test('names the run that produced it', () {
      expect(
        resolveRunId(_assistant('m1', run: 'run-1'), const {}),
        equals('run-1'),
      );
    });

    test('does not borrow a run from the user message before it', () {
      // The preceding user message's association advances to the last segment
      // of a tool loop, so borrowing it would file an early segment's reply
      // under a run that did not write it.
      expect(
        resolveRunId(
          _assistant('m1'),
          {'u1': _association('u1', 'run-9')},
        ),
        isNull,
      );
    });
  });

  group('a user tile', () {
    test('uses the run its turn was associated with', () {
      expect(
        resolveRunId(
          _user('u1', run: 'run-0'),
          {'u1': _association('u1', 'run-2')},
        ),
        equals('run-2'),
      );
    });

    test('falls back to its own run when nothing associated it', () {
      // A replayed user message is stamped with the run it opened; the live
      // optimistic echo is not, because it exists before that run does.
      expect(
        resolveRunId(_user('u1', run: 'run-0'), const {}),
        equals('run-0'),
      );
    });

    test('resolves to nothing when it has neither', () {
      expect(resolveRunId(_user('u1'), const {}), isNull);
    });
  });

  test('a turn spanning a tool loop resolves the same on both paths', () {
    // Live, the echo carries no run and the association names the final
    // segment. On reload the echo is stamped with the segment it opened, and
    // the association is the same. Both must reach the final segment, or the
    // actions on that tile would report different runs depending on whether
    // the thread had been reloaded.
    final states = {'u1': _association('u1', 'run-final')};

    expect(
      resolveRunId(_user('u1'), states),
      equals(resolveRunId(_user('u1', run: 'run-opening'), states)),
    );
    expect(resolveRunId(_user('u1'), states), equals('run-final'));
  });
}
