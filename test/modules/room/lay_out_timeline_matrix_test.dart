import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';

import '../../helpers/test_logger.dart';

// The layout half of the case matrix: for every shape the event layer can hand
// this function, the tiles it shows and the tile each band lands on.
//
// A row's name lists every case that reaches this layer as that row. Cases
// separated upstream often arrive here identical — `CONTENT("")`,
// `CONTENT("  ")` and no content at all are one empty message by the time the
// filter sees them, and a finished, failed or cancelled outcome is one parked
// tile. Naming them together keeps the ledger honest: one row is one thing
// checked, not seven.
//
// The properties asserted over every row are the point of the file. A band
// that lands on no tile is work the user watched happen and then could not
// find, and nothing else here would notice.
//
// They are a net, not the whole check. Run containment is enforced by the
// `tile.runId == inRun` filter in placement, and no valid row can defeat it, so
// the case that makes it load-bearing is an invalid input and lives beside the
// placement tests in `lay_out_timeline_test.dart`.

/// A case: what goes in, and what must come out.
typedef _Row = ({
  String case_,
  String what,
  List<ChatMessage> messages,
  // Band key → the run that band belongs to, so the properties can check
  // ownership without re-deriving it from the key.
  Map<String, String?> bands,
  Map<String, NoResponseTile> outcomes,
  StreamingState? streaming,
  String? activeRunId,
  List<String> tiles,
  // Tile id → band key.
  Map<String, String> placement,
});

TextMessage _assistant(
  String id, {
  String text = '',
  String? run,
  bool named = false,
  String thinking = '',
}) =>
    TextMessage(
      id: id,
      user: ChatUser.assistant,
      createdAt: null,
      text: text,
      thinkingText: thinking,
      runId: run,
      namedByToolCall: named,
    );

TextMessage _user(String id, {String text = 'ask'}) => TextMessage(
      id: id,
      user: ChatUser.user,
      createdAt: null,
      text: text,
    );

NoResponseTile _finished(String run) => NoResponseTile.finished(
      id: noResponseMessageId(run),
      thinkingText: '',
      runId: run,
    );

NoResponseTile _failed(String run) => NoResponseTile.failed(
      id: noResponseMessageId(run),
      thinkingText: '',
      errorDetail: 'boom',
      runId: run,
    );

NoResponseTile _cancelled(String run) => NoResponseTile.cancelled(
      id: noResponseMessageId(run),
      thinkingText: 'weighing it',
      runId: run,
    );

/// The unclaimed band of [run] — the one that collected while no message had
/// yet spoken.
String _unclaimed(String run) => noResponseMessageId(run);

List<_Row> _rows() => [
      // --- A: message kinds and content shapes -----------------------------
      (
        case_: 'A1/D4',
        what: 'the assistant says something',
        messages: [_user('u1'), _assistant('m1', text: 'Hello.', run: 'run-0')],
        bands: const {},
        outcomes: {'run-0': _finished('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm1'],
        placement: const {},
      ),
      (
        case_: 'A2/A6',
        what:
            'a reply with nothing to read, that no tool call named, keeps its '
            'tile',
        messages: [_user('u1'), _assistant('m1', text: '  ', run: 'run-0')],
        bands: const {},
        outcomes: {'run-0': _finished('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm1'],
        placement: const {},
      ),
      (
        case_: 'A3/A4/A5/A8/D3/D5/D6',
        what: 'a declaration, then the answer, with the work on the answer',
        messages: [
          _user('u1'),
          _assistant('m1', named: true, run: 'run-0', thinking: 'Let me look.'),
          _assistant('m2', text: 'Here.', run: 'run-0'),
        ],
        bands: {_unclaimed('run-0'): 'run-0'},
        outcomes: {'run-0': _finished('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm2'],
        placement: {'m2': _unclaimed('run-0')},
      ),
      (
        case_: 'A7',
        what: 'a named parent that carried content is an ordinary message',
        messages: [
          _user('u1'),
          _assistant('m1', text: 'One moment.', named: true, run: 'run-0'),
          _assistant('m2', text: 'Here.', run: 'run-0'),
        ],
        bands: {'m1': 'run-0'},
        outcomes: {'run-0': _finished('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm1', 'm2'],
        placement: {'m1': 'm1'},
      ),

      // --- B: call resolution x run outcome, single run ---------------------
      (
        case_: 'B1/B2/B3/B4/B5',
        what: 'a run that opened a declaration, worked, and never answered',
        messages: [_user('u1'), _assistant('m1', named: true, run: 'run-0')],
        bands: {_unclaimed('run-0'): 'run-0'},
        outcomes: {'run-0': _failed('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', noResponseMessageId('run-0')],
        placement: {noResponseMessageId('run-0'): _unclaimed('run-0')},
      ),
      (
        case_: 'B6',
        what: 'two tool rounds, then the answer, under one tile',
        messages: [
          _user('u1'),
          _assistant('m1', named: true, run: 'run-0', thinking: 'first'),
          _assistant('m2', named: true, run: 'run-0', thinking: 'second'),
          _assistant('m3', text: 'Here.', run: 'run-0'),
        ],
        bands: {_unclaimed('run-0'): 'run-0'},
        outcomes: {'run-0': _finished('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm3'],
        placement: {'m3': _unclaimed('run-0')},
      ),
      (
        case_: 'B7/D2/S3',
        what: 'a reply that spoke carries its own band',
        messages: [
          _user('u1'),
          _assistant('m1', text: 'One moment.', run: 'run-0'),
        ],
        bands: {'m1': 'run-0'},
        outcomes: {'run-0': _finished('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm1'],
        placement: {'m1': 'm1'},
      ),
      (
        case_: 'B8/E1/E3',
        what: 'a run that committed nothing at all still shows its outcome',
        messages: [_user('u1')],
        bands: {_unclaimed('run-0'): 'run-0'},
        outcomes: {'run-0': _cancelled('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', noResponseMessageId('run-0')],
        placement: {noResponseMessageId('run-0'): _unclaimed('run-0')},
      ),

      // --- C: across runs ---------------------------------------------------
      (
        case_: 'C1',
        what: 'a tool-only run, then a run that answers, stay separate',
        messages: [
          _user('u1'),
          _assistant('m1', named: true, run: 'run-0'),
          _assistant('m2', text: 'Here.', run: 'run-1'),
        ],
        bands: {_unclaimed('run-0'): 'run-0', 'm2': 'run-1'},
        outcomes: {'run-0': _finished('run-0'), 'run-1': _finished('run-1')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', noResponseMessageId('run-0'), 'm2'],
        placement: {
          noResponseMessageId('run-0'): _unclaimed('run-0'),
          'm2': 'm2'
        },
      ),
      (
        case_: 'C2',
        what: "a failed run's work stays off the next, unrelated answer",
        messages: [
          _user('u1'),
          _assistant('m1', named: true, run: 'run-0'),
          _user('u2', text: 'something else'),
          _assistant('m2', text: 'Here.', run: 'run-1'),
        ],
        bands: {_unclaimed('run-0'): 'run-0', 'm2': 'run-1'},
        outcomes: {'run-0': _failed('run-0'), 'run-1': _finished('run-1')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', noResponseMessageId('run-0'), 'u2', 'm2'],
        placement: {
          noResponseMessageId('run-0'): _unclaimed('run-0'),
          'm2': 'm2'
        },
      ),
      (
        case_: 'C3',
        what: 'a user message between runs does not disturb the band',
        messages: [
          _user('u1'),
          _assistant('m1', named: true, run: 'run-0'),
          _assistant('m2', text: 'Here.', run: 'run-0'),
          _user('u2', text: 'something else'),
          _assistant('m3', text: 'And here.', run: 'run-1'),
        ],
        bands: {_unclaimed('run-0'): 'run-0'},
        outcomes: {'run-0': _finished('run-0'), 'run-1': _finished('run-1')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm2', 'u2', 'm3'],
        placement: {'m2': _unclaimed('run-0')},
      ),

      // --- D: protocol variants ---------------------------------------------
      (
        case_: 'D1',
        what:
            'a run that produced nothing, and has no band either, still reports',
        messages: [_user('u1')],
        bands: const {},
        outcomes: {'run-0': _finished('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', noResponseMessageId('run-0')],
        placement: const {},
      ),

      // --- E: temporal -------------------------------------------------------
      (
        case_: 'E2',
        what: 'a committed reasoning-only reply keeps its tile, and no outcome '
            'joins it',
        messages: [
          _user('u1'),
          _assistant('m1', run: 'run-0', thinking: 'weighing it'),
        ],
        bands: {'m1': 'run-0'},
        outcomes: {'run-0': _cancelled('run-0')},
        streaming: null,
        activeRunId: null,
        tiles: ['u1', 'm1'],
        placement: {'m1': 'm1'},
      ),

      // --- Mid-stream: the window a terminal snapshot cannot see -------------
      (
        case_: 'S1',
        what: 'START, before any content',
        messages: [_user('u1')],
        bands: {_unclaimed('run-0'): 'run-0'},
        outcomes: const {},
        streaming: const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: '',
        ),
        activeRunId: 'run-0',
        tiles: ['u1', loadingMessageId],
        placement: {loadingMessageId: _unclaimed('run-0')},
      ),
      (
        case_: 'S2',
        what: 'CONTENT, with the reply part-written',
        messages: [_user('u1')],
        bands: {'m1': 'run-0'},
        outcomes: const {},
        streaming: const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: 'Half an ans',
          thinkingText: 'weighing it',
        ),
        activeRunId: 'run-0',
        tiles: ['u1', 'm1'],
        placement: {'m1': 'm1'},
      ),
    ];

void main() {
  late Logger logger;
  final rows = _rows();

  setUp(() => logger = testLogger());

  /// Lays [row] out, building a distinct tracker per band key so placement can
  /// be asserted by identity.
  ({List<RenderedTile> tiles, Map<String, ExecutionTracker> bands}) run(
    _Row row,
  ) {
    final bands = {
      for (final key in row.bands.keys)
        key: ExecutionTracker.historical(
          events: const [],
          origin: null,
          activities: const [],
          logger: logger,
        ),
    };
    addTearDown(() {
      for (final band in bands.values) {
        band.dispose();
      }
    });
    return (
      tiles: layOutTimeline(
        messages: row.messages,
        bands: bands,
        outcomes: row.outcomes,
        streaming: row.streaming,
        activeRunId: row.activeRunId,
        logger: logger,
      ),
      bands: bands,
    );
  }

  group('the case matrix', () {
    for (final row in rows) {
      test('${row.case_} — ${row.what}', () {
        final (:tiles, :bands) = run(row);

        expect(
          [for (final tile in tiles) tile.message.id],
          equals(row.tiles),
          reason: '${row.case_} shows the wrong tiles',
        );

        final byKey = {for (final e in bands.entries) e.value: e.key};
        expect(
          {
            for (final tile in tiles)
              if (tile.band case final band?) tile.message.id: byKey[band],
          },
          equals(row.placement),
          reason: '${row.case_} placed a band on the wrong tile',
        );
      });
    }
  });

  group('the properties every case must hold', () {
    test('no band renders nowhere', () {
      // The assertion whose absence let three regressions through a full
      // suite. A band that lands on no tile is work the user watched happen
      // and then could not find.
      for (final row in rows) {
        final (:tiles, :bands) = run(row);
        final rendered = {
          for (final tile in tiles)
            if (tile.band case final band?) band,
        };

        expect(
          rendered.length,
          equals(bands.length),
          reason: '${row.case_} dropped a band',
        );
      }
    });

    test('every band renders on a tile of its own run', () {
      for (final row in rows) {
        final (:tiles, :bands) = run(row);
        final runOf = {
          for (final e in bands.entries) e.value: row.bands[e.key],
        };

        for (final tile in tiles) {
          if (tile.band case final band?) {
            expect(
              tile.runId,
              equals(runOf[band]),
              reason: "${row.case_} put a band on another run's tile",
            );
          }
        }
      }
    });

    test('no tile renders two bands', () {
      for (final row in rows) {
        final (:tiles, bands: _) = run(row);
        final perTile = <String, int>{};

        for (final tile in tiles) {
          if (tile.band != null) {
            perTile.update(tile.message.id, (n) => n + 1, ifAbsent: () => 1);
          }
        }

        expect(
          perTile.values.where((n) => n > 1),
          isEmpty,
          reason: '${row.case_} gave one tile two bands',
        );
      }
    });

    test('every run that ended reaches a tile', () {
      for (final row in rows) {
        final (:tiles, bands: _) = run(row);
        final shown = {for (final tile in tiles) tile.runId};

        for (final runId in row.outcomes.keys) {
          if (runId == row.activeRunId) continue;
          expect(
            shown,
            contains(runId),
            reason: '${row.case_} left run $runId with no tile',
          );
        }
      }
    });
  });
}
