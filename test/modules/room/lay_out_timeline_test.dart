import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';
import 'package:soliplex_frontend/src/modules/room/lay_out_timeline.dart';
import 'package:soliplex_frontend/src/modules/room/execution_step.dart';
import 'package:soliplex_frontend/src/modules/room/execution_tracker.dart';

import '../../helpers/test_logger.dart';

/// An assistant reply. Empty text plus [named] is the message a response
/// opens only to give a tool call's `parentMessageId` a target.
TextMessage assistant(
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

TextMessage user(String id, {String text = 'ask', String? run}) => TextMessage(
      id: id,
      user: ChatUser.user,
      createdAt: null,
      text: text,
      runId: run,
    );

NoResponseTile outcome(String run) =>
    NoResponseTile.finished(runId: run, thinkingText: '');

/// The ids of the tiles laid out, in order.
List<String> idsOf(List<RenderedTile> tiles) =>
    [for (final tile in tiles) tile.message.id];

const _loggerName = 'lay_out_timeline_test';

void main() {
  late Logger logger;
  late _RecordingSink sink;

  setUp(() {
    sink = _RecordingSink(_loggerName);
    LogManager.instance.addSink(sink);
    addTearDown(() => LogManager.instance.removeSink(sink));
    logger = testLogger(_loggerName);
  });

  List<RenderedTile> layOut({
    List<ChatMessage> messages = const [],
    Map<String, ExecutionTracker> bands = const {},
    Map<String, NoResponseTile> outcomes = const {},
    StreamingState? streaming,
    String? activeRunId,
  }) =>
      layOutTimeline(
        messages: messages,
        bands: bands,
        outcomes: outcomes,
        streaming: streaming,
        activeRunId: activeRunId,
        logger: logger,
      );

  group('projecting the streaming reply', () {
    test('a thread at rest shows the messages it holds', () {
      final tiles = layOut(messages: [user('u1'), assistant('m1', text: 'Hi')]);

      expect(idsOf(tiles), equals(['u1', 'm1']));
    });

    test('a run awaiting its first text shows the loading tile', () {
      final tiles = layOut(
        messages: [user('u1')],
        streaming: const AwaitingText(),
        activeRunId: 'run-0',
      );

      expect(idsOf(tiles), equals(['u1', loadingMessageId]));
      expect(tiles.last.message, isA<LoadingMessage>());
    });

    test('a reply that has yet to say anything shows the loading tile', () {
      // The window between TEXT_MESSAGE_START and the first delta — which the
      // message that only names a tool call never leaves.
      final tiles = layOut(
        messages: [user('u1')],
        streaming: const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: '',
        ),
        activeRunId: 'run-0',
      );

      expect(idsOf(tiles), equals(['u1', loadingMessageId]));
    });

    test('a reply mid-stream shows its partial text and thinking', () {
      final tiles = layOut(
        messages: [user('u1')],
        streaming: const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: 'Half an ans',
          thinkingText: 'weighing it',
        ),
        activeRunId: 'run-0',
      );

      expect(idsOf(tiles), equals(['u1', 'm1']));
      final reply = tiles.last.message as TextMessage;
      expect(reply.text, equals('Half an ans'));
      expect(reply.thinkingText, equals('weighing it'));
      expect(reply.createdAt, isNull);
    });

    test('a reply mid-stream replaces the committed message of the same id',
        () {
      final tiles = layOut(
        messages: [user('u1'), assistant('m1', text: 'stale', run: 'run-0')],
        streaming: const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: 'fresh',
        ),
        activeRunId: 'run-0',
      );

      expect(idsOf(tiles), equals(['u1', 'm1']));
      expect((tiles.last.message as TextMessage).text, equals('fresh'));
    });

    test('both projected tiles carry the active run', () {
      final loading = layOut(
        streaming: const AwaitingText(),
        activeRunId: 'run-0',
      );
      final partial = layOut(
        streaming: const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: 'words',
        ),
        activeRunId: 'run-0',
      );

      expect(loading.single.message.runId, equals('run-0'));
      expect(partial.single.message.runId, equals('run-0'));
    });
  });

  group('leaving out the message that only names a tool call', () {
    test('an empty message a tool call named is not shown', () {
      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-0'),
        ],
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(idsOf(tiles), equals(['u1', 'm2']));
    });

    test('an empty message no tool call named keeps its tile', () {
      final tiles = layOut(
        messages: [user('u1'), assistant('m1', run: 'run-0')],
      );

      expect(idsOf(tiles), equals(['u1', 'm1']));
    });

    test('a named message that spoke keeps its tile', () {
      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', text: 'One moment.', named: true, run: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-0'),
        ],
      );

      expect(idsOf(tiles), equals(['u1', 'm1', 'm2']));
    });
  });

  group('guaranteeing a tile for every run that ended', () {
    test('a run whose only message was left out gets its parked outcome', () {
      final tiles = layOut(
        messages: [user('u1'), assistant('m1', named: true, run: 'run-0')],
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(idsOf(tiles), equals(['u1', noResponseMessageId('run-0')]));
      expect(tiles.last.message.runId, equals('run-0'));
    });

    test('a run that answered gets no outcome', () {
      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-0'),
        ],
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(idsOf(tiles), equals(['u1', 'm2']));
    });

    test('the run still in flight gets no outcome', () {
      final tiles = layOut(
        messages: [user('u1'), assistant('m1', named: true, run: 'run-0')],
        outcomes: {'run-0': outcome('run-0')},
        streaming: const AwaitingText(),
        activeRunId: 'run-0',
      );

      expect(idsOf(tiles), equals(['u1', loadingMessageId]));
    });

    test('a run with nothing parked gets nothing', () {
      final tiles = layOut(
        messages: [user('u1'), assistant('m1', named: true, run: 'run-0')],
      );

      expect(idsOf(tiles), equals(['u1']));
    });

    test("the outcome takes the run's place, ahead of the next question", () {
      // A failed run followed by an unrelated question: the outcome belongs
      // where the run was, not after the turn that came next.
      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          user('u2'),
          assistant('m2', text: 'Here.', run: 'run-1'),
        ],
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(
        idsOf(tiles),
        equals(['u1', noResponseMessageId('run-0'), 'u2', 'm2']),
      );
    });

    test('two silent runs each get their own outcome, in order', () {
      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          assistant('m2', named: true, run: 'run-1'),
        ],
        outcomes: {'run-0': outcome('run-0'), 'run-1': outcome('run-1')},
      );

      expect(
        idsOf(tiles),
        equals([
          'u1',
          noResponseMessageId('run-0'),
          noResponseMessageId('run-1'),
        ]),
      );
    });

    test('a message-less run settles before the next run answers', () {
      // A cancel before the reply opened leaves the run with nothing committed,
      // so there is no message to sit beside. Its outcome still belongs where
      // the run was — not at the bottom, under an answer to a later question.
      final tiles = layOut(
        messages: [
          user('u1'),
          user('u2', text: 'something else'),
          assistant('m2', text: 'Here.', run: 'run-1'),
        ],
        outcomes: {'run-0': outcome('run-0'), 'run-1': outcome('run-1')},
      );

      expect(
        idsOf(tiles),
        equals(['u1', 'u2', noResponseMessageId('run-0'), 'm2']),
      );
    });

    test('an unparked run does not drag a later outcome above it', () {
      // A run with no parked outcome says nothing about when it ended, so it
      // cannot be read as "later than everything owed". Only the run still in
      // flight can be read that way, and it is named.
      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', text: 'Here.', run: 'run-0'),
          assistant('m2', named: true, run: 'run-1'),
        ],
        outcomes: {'run-1': outcome('run-1')},
      );

      expect(
        idsOf(tiles),
        equals(['u1', 'm1', noResponseMessageId('run-1')]),
      );
    });

    test('a message-less run settles while a later run is still live', () {
      final tiles = layOut(
        messages: [user('u1'), user('u2', text: 'something else')],
        outcomes: {'run-0': outcome('run-0')},
        streaming: const AwaitingText(),
        activeRunId: 'run-1',
      );

      expect(
        idsOf(tiles),
        equals(['u1', 'u2', noResponseMessageId('run-0'), loadingMessageId]),
      );
    });

    test('a run that left no message at all still gets its outcome', () {
      // A cancel before the reply opened, and a run whose only output was
      // reasoning: nothing was ever committed under the run.
      final tiles = layOut(
        messages: [user('u1')],
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(idsOf(tiles), equals(['u1', noResponseMessageId('run-0')]));
    });

    test('a failed run with work after its reply reports the failure once', () {
      // The reply spoke in an earlier response; the run's last response thought
      // and then failed, so that work has no reply of its own and the outcome
      // tile hosts it. That tile already says the run failed — an error row
      // beside it would say so twice, and it appears only once a later message
      // makes the layout settle the run a second time.
      final trailing = ExecutionTracker.historical(
        unfinishedAs: StepStatus.failed,
        events: const [
          (event: ThinkingStarted(), timestamp: null),
          (event: ThinkingContent(delta: 'one more check'), timestamp: null),
        ],
        origin: null,
        activities: const [],
        logger: logger,
      );
      addTearDown(trailing.dispose);

      final tiles = layOut(
        messages: [
          user('u1', run: 'run-0'),
          assistant('m1', text: 'Let me look.', run: 'run-0'),
          user('u2', run: 'run-1'),
          assistant('m2', text: 'Hi.', run: 'run-1'),
        ],
        bands: {noResponseMessageId('run-0'): trailing},
        outcomes: {
          'run-0': NoResponseTile.failed(
            runId: 'run-0',
            thinkingText: '',
            errorDetail: 'the model stream broke off',
          ),
          'run-1': outcome('run-1'),
        },
      );

      expect(
        idsOf(tiles),
        equals(['u1', 'm1', noResponseMessageId('run-0'), 'u2', 'm2']),
      );
    });

    test('the outcome closes its run, after its other rows', () {
      // The outcome is the last band-capable position in its run, which is
      // what lets an unclaimed band fall back to it. It still precedes the
      // next run: the run it belongs to is over.
      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          ErrorMessage.create(id: 'e1', message: 'boom', runId: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-1'),
        ],
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(
        idsOf(tiles),
        equals(['u1', 'e1', noResponseMessageId('run-0'), 'm2']),
      );
    });

    group('showing that a run failed', () {
      NoResponseTile failed(String run) => NoResponseTile.failed(
            runId: run,
            thinkingText: '',
            errorDetail: 'upstream said no',
          );

      test('a failed run with nothing to show says so once', () {
        // One failure, one row. A failed outcome beside a separate error row
        // reports the same thing twice.
        final tiles = layOut(
          messages: [user('u1'), assistant('m1', named: true, run: 'run-0')],
          outcomes: {'run-0': failed('run-0')},
        );

        expect(idsOf(tiles), equals(['u1', noResponseMessageId('run-0')]));
      });

      test(
          'a failed run that answered keeps the answer and reports the '
          'failure beside it', () {
        // The reply stands for the run, so the outcome tile is suppressed —
        // but the run still failed, and saying nothing about it loses the
        // only account of why.
        final tiles = layOut(
          messages: [user('u1'), assistant('m1', text: 'Here.', run: 'run-0')],
          outcomes: {'run-0': failed('run-0')},
        );

        expect(idsOf(tiles), equals(['u1', 'm1', runErrorMessageId('run-0')]));
        final error = tiles.last.message as ErrorMessage;
        expect(error.errorText, equals('upstream said no'));
        expect(error.runId, equals('run-0'));
      });

      test('a failed run already reporting itself is not reported twice', () {
        // A tile that says the run failed carries the detail already. Adding
        // a second row beside it states one failure twice.
        final tiles = layOut(
          messages: [
            user('u1'),
            NoResponseTile.failed(
              runId: 'run-0',
              thinkingText: '',
              errorDetail: 'upstream said no',
            ),
          ],
          outcomes: {'run-0': failed('run-0')},
        );

        expect(idsOf(tiles), equals(['u1', noResponseMessageId('run-0')]));
      });

      test('a run that finished normally reports nothing extra', () {
        final tiles = layOut(
          messages: [user('u1'), assistant('m1', text: 'Here.', run: 'run-0')],
          outcomes: {'run-0': outcome('run-0')},
        );

        expect(idsOf(tiles), equals(['u1', 'm1']));
      });

      test('the run still in flight reports no failure', () {
        final tiles = layOut(
          messages: [user('u1'), assistant('m1', text: 'Here.', run: 'run-0')],
          outcomes: {'run-0': failed('run-0')},
          activeRunId: 'run-0',
        );

        expect(idsOf(tiles), equals(['u1', 'm1']));
      });
    });

    group('what stands in for a run, and what does not', () {
      List<String> withSurvivor(ChatMessage survivor) => idsOf(
            layOut(
              messages: [
                user('u1'),
                assistant('m1', named: true, run: 'run-0'),
                survivor,
              ],
              outcomes: {'run-0': outcome('run-0')},
            ),
          );

      test('an assistant reply stands in for its run', () {
        expect(
          withSurvivor(assistant('m2', text: 'Here.', run: 'run-0')),
          equals(['u1', 'm2']),
        );
      });

      test('an outcome tile already in the list stands in for its run', () {
        expect(
          withSurvivor(
            NoResponseTile.finished(
              runId: 'run-0',
              thinkingText: '',
            ),
          ),
          equals(['u1', noResponseMessageId('run-0')]),
        );
      });

      test('a user message does not stand in for a run', () {
        // It hosts no band, so suppressing on one would strand the run's work.
        expect(
          withSurvivor(user('u2', run: 'run-0')),
          equals(['u1', 'u2', noResponseMessageId('run-0')]),
        );
      });

      test('an error row does not stand in for a run', () {
        expect(
          withSurvivor(
            ErrorMessage.create(id: 'e1', message: 'boom', runId: 'run-0'),
          ),
          equals(['u1', 'e1', noResponseMessageId('run-0')]),
        );
      });

      test('a dropped-event row does not stand in for a run', () {
        expect(
          withSurvivor(
            DroppedEventMessage.create(
              id: 'd1',
              source: DropSource.decode,
              reason: 'bad',
              runId: 'run-0',
            ),
          ),
          equals(['u1', 'd1', noResponseMessageId('run-0')]),
        );
      });

      test('a tool call row does not stand in for a run', () {
        expect(
          withSurvivor(
            ToolCallMessage.create(
              id: 't1',
              toolCalls: const [],
              runId: 'run-0',
            ),
          ),
          equals(['u1', 't1', noResponseMessageId('run-0')]),
        );
      });
    });
  });

  group('placing the band', () {
    ExecutionTracker band() {
      final tracker = ExecutionTracker.historical(
        unfinishedAs: StepStatus.failed,
        events: const [],
        origin: null,
        activities: const [],
        logger: logger,
      );
      addTearDown(tracker.dispose);
      return tracker;
    }

    /// The band each tile received, by tile id. Tiles with no band are left
    /// out, so an assertion names exactly the pairings it expects.
    Map<String, ExecutionTracker> bandsOf(List<RenderedTile> tiles) => {
          for (final tile in tiles)
            if (tile.band case final band?) tile.message.id: band,
        };

    test('a band claimed by a reply renders on that reply', () {
      final b = band();

      final tiles = layOut(
        messages: [user('u1'), assistant('m1', text: 'Here.', run: 'run-0')],
        bands: {'m1': b},
      );

      expect(bandsOf(tiles), equals({'m1': b}));
    });

    test('an unclaimed band reaches the reply that eventually spoke', () {
      // A response that opened with a tool call: the band collected under the
      // run's key while the declaration stood, and belongs to the reply.
      final b = band();

      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-0'),
        ],
        bands: {noResponseMessageId('run-0'): b},
      );

      expect(bandsOf(tiles), equals({'m2': b}));
    });

    test('an unclaimed band with no reply falls back to the outcome', () {
      final b = band();

      final tiles = layOut(
        messages: [user('u1'), assistant('m1', named: true, run: 'run-0')],
        bands: {noResponseMessageId('run-0'): b},
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(bandsOf(tiles), equals({noResponseMessageId('run-0'): b}));
    });

    test('an unclaimed band renders on the loading tile while the run is live',
        () {
      final b = band();

      final tiles = layOut(
        messages: [user('u1')],
        bands: {noResponseMessageId('run-0'): b},
        streaming: const AwaitingText(),
        activeRunId: 'run-0',
      );

      expect(bandsOf(tiles), equals({loadingMessageId: b}));
    });

    test(
        "a later response's band renders on the loading tile, not the reply "
        'before it', () {
      // A run that spoke, called a tool and is now in its next response: the
      // reply holds the band of the response it spoke in, and the response
      // still open is keyed by the run. That one belongs at the end of the
      // run, where it is happening, not at the start where the reply already
      // holds a band.
      final reply = band();
      final open = band();

      final tiles = layOut(
        messages: [
          user('u1', run: 'run-0'),
          assistant('m1', text: 'Let me look.', run: 'run-0'),
        ],
        bands: {'m1': reply, noResponseMessageId('run-0'): open},
        streaming: const AwaitingText(),
        activeRunId: 'run-0',
      );

      expect(bandsOf(tiles), equals({'m1': reply, loadingMessageId: open}));
      expect(sink.warnings, isEmpty);
    });

    test("a later response's band renders on the reply streaming for it", () {
      final reply = band();
      final open = band();

      final tiles = layOut(
        messages: [
          user('u1', run: 'run-0'),
          assistant('m1', text: 'Let me look.', run: 'run-0'),
        ],
        bands: {'m1': reply, noResponseMessageId('run-0'): open},
        streaming: const TextStreaming(
          messageId: 'm2',
          user: ChatUser.assistant,
          text: 'Both sources agree.',
        ),
        activeRunId: 'run-0',
      );

      expect(bandsOf(tiles), equals({'m1': reply, 'm2': open}));
      expect(sink.warnings, isEmpty);
    });

    test('an unclaimed band never crosses into the next run', () {
      // The run that worked and went quiet keeps its own work; the answer to
      // the question after it stays clean.
      final b = band();

      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          user('u2'),
          assistant('m2', text: 'Here.', run: 'run-1'),
        ],
        bands: {noResponseMessageId('run-0'): b},
        outcomes: {'run-0': outcome('run-0')},
      );

      expect(bandsOf(tiles), equals({noResponseMessageId('run-0'): b}));
    });

    test('a claimed band stays on its own reply, not a later one', () {
      final first = band();
      final second = band();

      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', text: 'One moment.', run: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-0'),
        ],
        bands: {'m1': first, 'm2': second},
      );

      expect(bandsOf(tiles), equals({'m1': first, 'm2': second}));
    });

    test('placement skips a user tile and a diagnostic row', () {
      final b = band();

      final tiles = layOut(
        messages: [
          user('u1', run: 'run-0'),
          ErrorMessage.create(id: 'e1', message: 'boom', runId: 'run-0'),
          assistant('m1', text: 'Here.', run: 'run-0'),
        ],
        bands: {noResponseMessageId('run-0'): b},
      );

      expect(bandsOf(tiles), equals({'m1': b}));
    });

    test('a band keyed to an outcome tile renders on that tile', () {
      // The key a run's unclaimed band carries is also the id its outcome tile
      // carries. When the list already holds that tile, the key names it —
      // reading the key as "the run's start" instead would hand its captured
      // reasoning to a reply that said something else.
      final b = band();
      final parked = NoResponseTile.finished(
        runId: 'run-0',
        thinkingText: 'weighing it',
      );

      final tiles = layOut(
        messages: [assistant('m1', text: 'Here.', run: 'run-0'), parked],
        bands: {noResponseMessageId('run-0'): b},
      );

      expect(idsOf(tiles), equals(['m1', noResponseMessageId('run-0')]));
      expect(bandsOf(tiles), equals({noResponseMessageId('run-0'): b}));
    });

    test('an unclaimed band is dropped, never hoisted onto the next run', () {
      // The run worked and went quiet, and nothing was parked for it — so it
      // has no tile of its own. Reaching forward for the next run's answer
      // would put an abandoned run's steps above an unrelated reply, which is
      // the one thing a band must never do. Dropping it reports the defect
      // instead of hiding it in the wrong place.
      final b = band();

      final tiles = layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          // run-0's only survivor hosts no band, so reaching forward would
          // leave its run behind.
          ErrorMessage.create(id: 'e1', message: 'boom', runId: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-1'),
        ],
        bands: {noResponseMessageId('run-0'): b},
      );

      expect(idsOf(tiles), equals(['u1', 'e1', 'm2']));
      expect(bandsOf(tiles), isEmpty);
      expect(
        sink.warnings.single.attributes['band'],
        equals(noResponseMessageId('run-0')),
      );
    });

    test('a band keyed to no shown tile is reported and dropped', () {
      final b = band();

      final tiles = layOut(
        messages: [user('u1'), assistant('m1', text: 'Here.', run: 'run-0')],
        bands: {'gone': b},
      );

      expect(bandsOf(tiles), isEmpty);
      expect(
        sink.warnings.single.message,
        contains('no tile to render on'),
      );
      expect(sink.warnings.single.attributes['band'], equals('gone'));
    });

    test('a second band for one tile is reported and dropped', () {
      // Only one band renders per tile, so a second arriving for the same one
      // is a defect upstream rather than something to silently overwrite.
      final claimed = band();
      final unclaimed = band();

      final tiles = layOut(
        messages: [user('u1'), assistant('m1', text: 'Here.', run: 'run-0')],
        bands: {'m1': claimed, noResponseMessageId('run-0'): unclaimed},
      );

      expect(bandsOf(tiles), equals({'m1': claimed}));
      expect(
        sink.warnings.single.attributes['band'],
        equals(noResponseMessageId('run-0')),
      );
      expect(sink.warnings.single.attributes['tile'], equals('m1'));
    });

    test('a run laid out normally reports nothing', () {
      layOut(
        messages: [
          user('u1'),
          assistant('m1', named: true, run: 'run-0'),
          assistant('m2', text: 'Here.', run: 'run-0'),
        ],
        bands: {noResponseMessageId('run-0'): band()},
      );

      expect(sink.warnings, isEmpty);
    });
  });
}

/// Captures records from this file's logger, ignoring the other traffic the
/// shared `LogManager` sees so assertions stay strict.
class _RecordingSink implements LogSink {
  _RecordingSink(this.loggerName);

  final String loggerName;
  final List<LogRecord> records = [];

  List<LogRecord> get warnings =>
      records.where((r) => r.level == LogLevel.warning).toList();

  @override
  void write(LogRecord record) {
    if (record.loggerName == loggerName) records.add(record);
  }

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}
