import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';

import '../../helpers/test_logger.dart';

/// Stands for the run that holds a pending slot — production passes the run's
/// execution tracker, which outlives its message being named.
ExecutionTracker aRun() => ExecutionTracker.historical(
      events: const [],
      origin: null,
      activities: const [],
      logger: testLogger(),
    );

void main() {
  group('MessageExpansions', () {
    late MessageExpansions expansions;

    setUp(() => expansions = MessageExpansions());

    test('timeline default is false and round-trips', () {
      final m = expansions.forMessage('r', 'm');
      expect(m.timelineExpanded, isFalse);
      m.timelineExpanded = true;
      expect(m.timelineExpanded, isTrue);
      m.timelineExpanded = false;
      expect(m.timelineExpanded, isFalse);
    });

    test('thinking default is false and round-trips', () {
      final m = expansions.forMessage('r', 'm');
      expect(m.thinkingExpanded, isFalse);
      m.thinkingExpanded = true;
      expect(m.thinkingExpanded, isTrue);
    });

    test('source default is false; toggle adds then removes', () {
      final m = expansions.forMessage('r', 'm');
      expect(m.isSourceExpanded('a1'), isFalse);
      m.toggleSource('a1');
      expect(m.isSourceExpanded('a1'), isTrue);
      m.toggleSource('a1');
      expect(m.isSourceExpanded('a1'), isFalse);
    });

    test('handles keyed by (roomId, messageId) are independent', () {
      expansions.forMessage('room-1', 'msg').timelineExpanded = true;
      expect(expansions.forMessage('room-1', 'msg').timelineExpanded, isTrue);
      expect(expansions.forMessage('room-2', 'msg').timelineExpanded, isFalse);
      expect(
          expansions.forMessage('room-1', 'other').timelineExpanded, isFalse);
    });

    test('the three state kinds do not cross-contaminate', () {
      final m = expansions.forMessage('r', 'm');
      m.timelineExpanded = true;
      expect(m.thinkingExpanded, isFalse);
      m.thinkingExpanded = true;
      expect(m.isSourceExpanded('a1'), isFalse);
      m.toggleSource('a1');
      expect(m.timelineExpanded, isTrue);
      expect(m.thinkingExpanded, isTrue);
      expect(m.isSourceExpanded('a1'), isTrue);
    });

    test('multiple source activities tracked independently per message', () {
      final m = expansions.forMessage('r', 'm');
      m.toggleSource('a1');
      m.toggleSource('a2');
      expect(m.isSourceExpanded('a1'), isTrue);
      expect(m.isSourceExpanded('a2'), isTrue);
      m.toggleSource('a1');
      expect(m.isSourceExpanded('a1'), isFalse);
      expect(m.isSourceExpanded('a2'), isTrue);
    });

    test('setSourceExpanded(false) on unknown key is a no-op', () {
      final m = expansions.forMessage('r', 'm');
      m.setSourceExpanded('never-added', false);
      expect(m.isSourceExpanded('never-added'), isFalse);
    });

    test('two handles to the same message share state', () {
      final a = expansions.forMessage('r', 'm');
      final b = expansions.forMessage('r', 'm');
      a.timelineExpanded = true;
      expect(b.timelineExpanded, isTrue);
      b.toggleSource('a1');
      expect(a.isSourceExpanded('a1'), isTrue);
    });

    test('entries beyond maxEntries evict oldest-inserted (FIFO)', () {
      for (var i = 0; i < MessageExpansions.maxEntries; i++) {
        expansions.forMessage('r', 'm$i').timelineExpanded = true;
      }
      expect(expansions.debugHasStateFor('r', 'm0'), isTrue);

      // The next new entry evicts the oldest-inserted (m0).
      expansions.forMessage('r', 'new').timelineExpanded = true;
      expect(expansions.debugHasStateFor('r', 'm0'), isFalse);
      expect(expansions.debugHasStateFor('r', 'new'), isTrue);
      expect(expansions.debugHasStateFor('r', 'm1'), isTrue);
    });

    group('the pending slot', () {
      final run = aRun();

      test('all three state kinds move together', () {
        final pending = expansions.pendingFor(run, 'r')
          ..timelineExpanded = true
          ..thinkingExpanded = true;
        pending.setSourceExpanded('src', true);

        expansions.adoptPending(run, 'r', 'm');

        final adopted = expansions.forMessage('r', 'm');
        expect(adopted.timelineExpanded, isTrue);
        expect(adopted.thinkingExpanded, isTrue);
        expect(adopted.isSourceExpanded('src'), isTrue);
      });

      test('another run cannot take it', () {
        // A tile for some older message mounting mid-run must not adopt the
        // state the live run wrote, or the reply loses it.
        expansions.pendingFor(run, 'r').timelineExpanded = true;

        expansions.adoptPending(aRun(), 'r', 'other');

        expect(expansions.debugHasStateFor('r', 'other'), isFalse);
        expansions.adoptPending(run, 'r', 'm');
        expect(expansions.forMessage('r', 'm').timelineExpanded, isTrue);
      });

      test('a second adoption finds nothing left to take', () {
        // Both the timeline and the thinking block adopt on mount; whichever
        // runs second reads the entry the first one wrote.
        expansions.pendingFor(run, 'r').thinkingExpanded = true;

        expansions.adoptPending(run, 'r', 'm');
        expansions.adoptPending(run, 'r', 'other');

        expect(expansions.debugHasStateFor('r', 'other'), isFalse);
        expect(expansions.forMessage('r', 'm').thinkingExpanded, isTrue);
      });

      test('a new run starts from closed', () {
        expansions.pendingFor(run, 'r').timelineExpanded = true;

        final next = aRun();
        expect(expansions.pendingFor(next, 'r').timelineExpanded, isFalse);
      });

      test('adopting adds to what the message already has', () {
        // Both are the user's: one opened before the run, one during it.
        expansions.forMessage('r', 'm').thinkingExpanded = true;
        expansions.pendingFor(run, 'r').timelineExpanded = true;

        expansions.adoptPending(run, 'r', 'm');

        final adopted = expansions.forMessage('r', 'm');
        expect(adopted.thinkingExpanded, isTrue);
        expect(adopted.timelineExpanded, isTrue);
      });

      test("a run in another room does not take this one's pending", () {
        // Rooms can stream at once, and the slot is keyed per room — so the
        // claim on it has to be too, or whichever run started last takes the
        // other's open block.
        expansions.pendingFor(run, 'room-a').timelineExpanded = true;
        expansions.pendingFor(aRun(), 'room-b').thinkingExpanded = true;

        expansions.adoptPending(run, 'room-a', 'm');

        expect(expansions.forMessage('room-a', 'm').timelineExpanded, isTrue);
      });
    });
  });
}
