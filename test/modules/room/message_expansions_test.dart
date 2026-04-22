import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';

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
  });
}
