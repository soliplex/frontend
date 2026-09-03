import 'package:soliplex_client/src/application/no_response_synthesis.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:test/test.dart';

void main() {
  group('synthesize…NoResponse', () {
    late Conversation conversation;

    setUp(() {
      conversation = Conversation.empty(threadId: 'thread-1');
    });

    group('decline conditions', () {
      test('declines when streaming is TextStreaming', () {
        const streaming = TextStreaming(
          messageId: 'msg-1',
          user: ChatUser.assistant,
          text: 'partial reply',
          thinkingText: 'reasoning',
        );

        final result = synthesizeFinishedNoResponse(
          conversation: conversation,
          streaming: streaming,
          runId: 'run-1',
        );

        expect(result.synthesized, isFalse);
        expect(
          result.conversation.messages.whereType<NoResponseTile>(),
          isEmpty,
        );
      });

      test('declines when buffered thinking is empty', () {
        const streaming = AwaitingText();

        final result = synthesizeFinishedNoResponse(
          conversation: conversation,
          streaming: streaming,
          runId: 'run-1',
        );

        expect(result.synthesized, isFalse);
        expect(
          result.conversation.messages.whereType<NoResponseTile>(),
          isEmpty,
        );
      });

      test('declines when a tool call is pending', () {
        final convo = conversation.withToolCall(
          const ToolCallInfo(
            id: 'tc1',
            name: 'search',
          ),
        );

        final result = synthesizeFinishedNoResponse(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
        );

        expect(result.synthesized, isFalse);
        expect(
          result.conversation.messages.whereType<NoResponseTile>(),
          isEmpty,
        );
      });

      test('declines when a tool call is streaming', () {
        final convo = conversation.withToolCall(
          const ToolCallInfo(
            id: 'tc1',
            name: 'search',
            status: ToolCallStatus.streaming,
          ),
        );

        final result = synthesizeFinishedNoResponse(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
        );

        expect(result.synthesized, isFalse);
      });

      test('declines when a tool call is executing', () {
        final convo = conversation.withToolCall(
          const ToolCallInfo(
            id: 'tc1',
            name: 'search',
            status: ToolCallStatus.executing,
          ),
        );

        final result = synthesizeFinishedNoResponse(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
        );

        expect(result.synthesized, isFalse);
      });

      test('does NOT decline when all tool calls are completed', () {
        final convo = conversation.withToolCall(
          const ToolCallInfo(
            id: 'tc1',
            name: 'search',
            status: ToolCallStatus.completed,
            result: 'done',
          ),
        );

        final result = synthesizeFinishedNoResponse(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
        );

        expect(result.synthesized, isTrue);
      });
    });

    group('synthesis', () {
      test(
          'synthesizeFinishedNoResponse appends a finished tile with thinking '
          'and stable id', () {
        final result = synthesizeFinishedNoResponse(
          conversation: conversation,
          streaming: const AwaitingText(bufferedThinkingText: 'I considered'),
          runId: 'run-42',
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.id, equals(noResponseMessageId('run-42')));
        expect(tile.reason, equals(TerminalReason.finished));
        expect(tile.thinkingText, equals('I considered'));
        expect(tile.errorDetail, isNull);
      });

      test(
          'synthesizeFailedNoResponse appends a failed tile with errorDetail '
          'propagated', () {
        final result = synthesizeFailedNoResponse(
          conversation: conversation,
          streaming: const AwaitingText(bufferedThinkingText: 'partial'),
          runId: 'run-42',
          errorDetail: 'boom',
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.reason, equals(TerminalReason.failed));
        expect(tile.errorDetail, equals('boom'));
      });

      test(
          'synthesizeCancelledNoResponse appends a cancelled tile with no '
          'errorDetail', () {
        final result = synthesizeCancelledNoResponse(
          conversation: conversation,
          streaming: const AwaitingText(bufferedThinkingText: 'partial'),
          runId: 'run-42',
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.reason, equals(TerminalReason.cancelled));
        // Buffered thinking is the only thing a cancelled run produced, so the
        // tile is what carries it — the streaming buffer is reset behind it.
        expect(tile.thinkingText, equals('partial'));
        expect(tile.errorDetail, isNull);
      });

      test(
          'synthesizeCancelledNoResponse appends a tile once thinking is '
          'streaming, before any content arrives', () {
        // The UI shows a Thinking indicator from the reasoning-start event, so
        // a Stop pressed before the first content event must still leave an
        // account of the run. Declining here blanks the whole exchange: the
        // buffered thinking is what the tile would have carried, and without a
        // tile there is nothing else holding it.
        final result = synthesizeCancelledNoResponse(
          conversation: conversation,
          streaming: const AwaitingText(isThinkingStreaming: true),
          runId: 'run-42',
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.reason, equals(TerminalReason.cancelled));
        expect(tile.hasThinkingText, isFalse);
      });

      test(
          'synthesizeCancelledNoResponse appends a tile with a tool call still '
          'open', () {
        // A cancel taken while a backend tool call is in flight still has
        // thinking the user was reading, and nothing else keeps it: the
        // tool-call guard exists for a client-side yield, where the tool card
        // is the response — and that path never reaches here, because
        // cancelRun handles ToolYieldingState in its own branch.
        final convo = conversation.withToolCall(
          const ToolCallInfo(id: 'tc1', name: 'search'),
        );

        final result = synthesizeCancelledNoResponse(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'I considered'),
          runId: 'run-42',
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.reason, equals(TerminalReason.cancelled));
        expect(tile.thinkingText, equals('I considered'));
      });

      test(
          'synthesizeCancelledNoResponse still declines before thinking '
          'starts', () {
        // Nothing has been shown yet, so there is nothing to preserve and the
        // user knows they pressed Stop.
        final result = synthesizeCancelledNoResponse(
          conversation: conversation,
          streaming: const AwaitingText(),
          runId: 'run-42',
        );

        expect(result.synthesized, isFalse);
        expect(
          result.conversation.messages.whereType<NoResponseTile>(),
          isEmpty,
        );
      });
    });
  });

  group('commitPartialTextOnTerminal', () {
    late Conversation conversation;

    setUp(() {
      conversation = Conversation.empty(threadId: 'thread-1');
    });

    test('commits nothing when the reply holds neither text nor thinking', () {
      // A terminal that landed between TEXT_MESSAGE_START and the first
      // delta. There is nothing on screen to keep, and an empty reply would
      // state that the assistant answered with nothing where the truth is
      // that it was stopped or cut off.
      const streaming = TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: '',
      );

      final result = commitPartialTextOnTerminal(
        conversation: conversation,
        streaming: streaming,
        runId: 'run-1',
        terminalEvent: 'cancelRun',
      );

      expect(result.messages, isEmpty);
    });

    test('commits a reply that holds thinking but no text', () {
      // The thinking the user watched stream is on screen, and this commit is
      // its only carrier, so it survives the terminal even with no reply text.
      const streaming = TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: '',
        thinkingText: 'reasoning the user watched',
      );

      final result = commitPartialTextOnTerminal(
        conversation: conversation,
        streaming: streaming,
        runId: 'run-1',
        terminalEvent: 'cancelRun',
      );

      final message = result.messages.single as TextMessage;
      expect(message.text, isEmpty);
      expect(message.thinkingText, 'reasoning the user watched');
    });

    test('returns conversation unchanged when streaming is AwaitingText', () {
      const streaming = AwaitingText(bufferedThinkingText: 'thinking');

      final result = commitPartialTextOnTerminal(
        conversation: conversation,
        streaming: streaming,
        runId: 'run-1',
        terminalEvent: 'cancelRun',
      );

      expect(result, same(conversation));
    });

    test(
        'commits in-flight TextStreaming as a finalized TextMessage with '
        'preserved fields', () {
      const streaming = TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'partial reply',
        thinkingText: 'partial reasoning',
      );

      final result = commitPartialTextOnTerminal(
        conversation: conversation,
        streaming: streaming,
        runId: 'run-1',
        terminalEvent: 'cancelRun',
      );

      expect(result.messages, hasLength(1));
      final committed = result.messages.first as TextMessage;
      expect(committed.id, equals('msg-1'));
      expect(committed.text, equals('partial reply'));
      expect(committed.thinkingText, equals('partial reasoning'));
      expect(committed.user, equals(ChatUser.assistant));
    });

    test(
        'is idempotent when a message with the streaming id already exists '
        '(e.g. a TextMessageEnd already finalized it)', () {
      final existing = TextMessage.create(
        id: 'msg-1',
        user: ChatUser.assistant,
        text: 'finalized',
      );
      final convo = conversation.withAppendedMessage(existing);
      const streaming = TextStreaming(
        messageId: 'msg-1',
        user: ChatUser.assistant,
        text: 'partial',
      );

      final result = commitPartialTextOnTerminal(
        conversation: convo,
        streaming: streaming,
        runId: 'run-1',
        terminalEvent: 'cancelRun',
      );

      expect(result, same(convo));
      expect(result.messages, hasLength(1));
      expect((result.messages.first as TextMessage).text, equals('finalized'));
    });
  });
}
