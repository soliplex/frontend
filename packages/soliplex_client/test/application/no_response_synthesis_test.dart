import 'package:soliplex_client/src/application/no_response_synthesis.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:test/test.dart';

void main() {
  group('synthesizeNoResponseIfNeeded', () {
    late Conversation conversation;

    setUp(() {
      conversation = Conversation.empty(threadId: 'thread-1');
    });

    group('preconditions', () {
      test(
          'throws ArgumentError when reason is failed without '
          'terminalErrorDetail', () {
        expect(
          () => synthesizeNoResponseIfNeeded(
            conversation: conversation,
            streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
            runId: 'run-1',
            reason: TerminalReason.failed,
          ),
          throwsArgumentError,
        );
      });

      test(
          'throws ArgumentError when reason is finished but '
          'terminalErrorDetail is set', () {
        expect(
          () => synthesizeNoResponseIfNeeded(
            conversation: conversation,
            streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
            runId: 'run-1',
            reason: TerminalReason.finished,
            terminalErrorDetail: 'unexpected detail',
          ),
          throwsArgumentError,
        );
      });

      test(
          'throws ArgumentError when reason is cancelled but '
          'terminalErrorDetail is set', () {
        expect(
          () => synthesizeNoResponseIfNeeded(
            conversation: conversation,
            streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
            runId: 'run-1',
            reason: TerminalReason.cancelled,
            terminalErrorDetail: 'unexpected detail',
          ),
          throwsArgumentError,
        );
      });
    });

    group('decline conditions', () {
      test('declines when streaming is TextStreaming', () {
        const streaming = TextStreaming(
          messageId: 'msg-1',
          user: ChatUser.assistant,
          text: 'partial reply',
          thinkingText: 'reasoning',
        );

        final result = synthesizeNoResponseIfNeeded(
          conversation: conversation,
          streaming: streaming,
          runId: 'run-1',
          reason: TerminalReason.finished,
        );

        expect(result.synthesized, isFalse);
        expect(result.conversation, same(conversation));
      });

      test('declines when buffered thinking is empty', () {
        const streaming = AwaitingText();

        final result = synthesizeNoResponseIfNeeded(
          conversation: conversation,
          streaming: streaming,
          runId: 'run-1',
          reason: TerminalReason.finished,
        );

        expect(result.synthesized, isFalse);
        expect(result.conversation, same(conversation));
      });

      test('declines when a tool call is pending', () {
        final convo = conversation.withToolCall(
          const ToolCallInfo(
            id: 'tc1',
            name: 'search',
          ),
        );

        final result = synthesizeNoResponseIfNeeded(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
          reason: TerminalReason.finished,
        );

        expect(result.synthesized, isFalse);
        expect(result.conversation, same(convo));
      });

      test('declines when a tool call is streaming', () {
        final convo = conversation.withToolCall(
          const ToolCallInfo(
            id: 'tc1',
            name: 'search',
            status: ToolCallStatus.streaming,
          ),
        );

        final result = synthesizeNoResponseIfNeeded(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
          reason: TerminalReason.finished,
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

        final result = synthesizeNoResponseIfNeeded(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
          reason: TerminalReason.finished,
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

        final result = synthesizeNoResponseIfNeeded(
          conversation: convo,
          streaming: const AwaitingText(bufferedThinkingText: 'thinking'),
          runId: 'run-1',
          reason: TerminalReason.finished,
        );

        expect(result.synthesized, isTrue);
      });
    });

    group('synthesis', () {
      test('appends NoResponseTile.finished with thinking and stable id', () {
        final result = synthesizeNoResponseIfNeeded(
          conversation: conversation,
          streaming: const AwaitingText(bufferedThinkingText: 'I considered'),
          runId: 'run-42',
          reason: TerminalReason.finished,
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.id, equals(noResponseMessageId('run-42')));
        expect(tile.reason, equals(TerminalReason.finished));
        expect(tile.thinkingText, equals('I considered'));
        expect(tile.errorDetail, isNull);
      });

      test('appends NoResponseTile.failed with errorDetail propagated', () {
        final result = synthesizeNoResponseIfNeeded(
          conversation: conversation,
          streaming: const AwaitingText(bufferedThinkingText: 'partial'),
          runId: 'run-42',
          reason: TerminalReason.failed,
          terminalErrorDetail: 'boom',
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.reason, equals(TerminalReason.failed));
        expect(tile.errorDetail, equals('boom'));
      });

      test('appends NoResponseTile.cancelled with no errorDetail', () {
        final result = synthesizeNoResponseIfNeeded(
          conversation: conversation,
          streaming: const AwaitingText(bufferedThinkingText: 'partial'),
          runId: 'run-42',
          reason: TerminalReason.cancelled,
        );

        expect(result.synthesized, isTrue);
        final tile = result.conversation.messages.last as NoResponseTile;
        expect(tile.reason, equals(TerminalReason.cancelled));
        expect(tile.errorDetail, isNull);
      });
    });
  });

  group('commitPartialTextOnTerminal', () {
    late Conversation conversation;

    setUp(() {
      conversation = Conversation.empty(threadId: 'thread-1');
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
