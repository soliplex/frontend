import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart'
    show loadingMessageId;
import 'package:soliplex_frontend/src/modules/room/message_expansions.dart';

import '../../helpers/replayed_band.dart';

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

    group('a band on the loading tile', () {
      test('keeps its own state, apart from every other band', () {
        final band = replayedBand();
        final other = replayedBand();
        addTearDown(band.dispose);
        addTearDown(other.dispose);

        expansions.forBand('r', loadingMessageId, band)
          ..timelineExpanded = true
          ..toggleSource('a1');

        final handle = expansions.forBand('r', loadingMessageId, band);
        expect(handle.timelineExpanded, isTrue);
        expect(handle.isSourceExpanded('a1'), isTrue);
        expect(
            expansions.forBand('r', loadingMessageId, other).timelineExpanded,
            isFalse);
      });

      test('hands its state to the message that first renders it', () {
        final band = replayedBand();
        addTearDown(band.dispose);
        expansions.forBand('r', loadingMessageId, band)
          ..thinkingExpanded = true
          ..toggleSource('a1');

        final reply = expansions.forBand('r', 'reply', band);

        expect(reply.thinkingExpanded, isTrue);
        expect(reply.isSourceExpanded('a1'), isTrue);
        expect(reply.timelineExpanded, isFalse);
        expect(expansions.debugHasStateFor('r', 'reply'), isTrue);
      });

      test('does not override what a message already stores', () {
        final band = replayedBand();
        addTearDown(band.dispose);
        expansions.forMessage('r', 'reply').timelineExpanded = true;
        expansions.forBand('r', loadingMessageId, band).thinkingExpanded = true;

        final reply = expansions.forBand('r', 'reply', band);

        expect(reply.timelineExpanded, isTrue);
        expect(reply.thinkingExpanded, isFalse);
      });

      test('counts against maxEntries once a message takes it', () {
        final band = replayedBand();
        addTearDown(band.dispose);
        for (var i = 0; i < MessageExpansions.maxEntries; i++) {
          expansions.forMessage('r', 'm$i').timelineExpanded = true;
        }
        expansions.forBand('r', loadingMessageId, band).timelineExpanded = true;

        expansions.forBand('r', 'reply', band);

        expect(expansions.debugHasStateFor('r', 'reply'), isTrue);
        expect(expansions.debugHasStateFor('r', 'm0'), isFalse);
        expect(expansions.debugHasStateFor('r', 'm1'), isTrue);
      });
    });
  });
}
