import 'package:soliplex_client/src/application/no_response_synthesis.dart';
import 'package:soliplex_client/src/application/streaming_state.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:test/test.dart';

void main() {
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

  group('parking a run outcome', () {
    final conversation = Conversation.empty(threadId: 't');

    test('a finished run parks a finished tile carrying its reasoning', () {
      final parked = parkFinishedOutcome(
        conversation: conversation,
        streaming: const AwaitingText(bufferedThinkingText: 'weighing it'),
        runId: 'run-0',
      ).runOutcomes['run-0']!;

      expect(parked.id, equals(noResponseMessageId('run-0')));
      expect(parked.runId, equals('run-0'));
      expect(parked.reason, equals(TerminalReason.finished));
      expect(parked.thinkingText, equals('weighing it'));
    });

    test('a cancelled run parks as cancelled', () {
      final parked = parkCancelledOutcome(
        conversation: conversation,
        streaming: const AwaitingText(bufferedThinkingText: 'weighing it'),
        runId: 'run-0',
      ).runOutcomes['run-0']!;

      expect(parked.reason, equals(TerminalReason.cancelled));
      expect(parked.thinkingText, equals('weighing it'));
    });

    test('a run that produced nothing at all still parks', () {
      // Whether the candidate is shown is decided where the whole thread is
      // visible. Declining to park here is what made a silent turn silent.
      final parked = parkFinishedOutcome(
        conversation: conversation,
        streaming: const AwaitingText(),
        runId: 'run-0',
      ).runOutcomes['run-0'];

      expect(parked, isNotNull);
      expect(parked!.thinkingText, isEmpty);
    });

    test('a run with a tool call still unresolved parks', () {
      // Whether the run is really over is the lifecycle's to say, not a guess
      // made from an unanswered call.
      final withCall = conversation.withToolCall(
        const ToolCallInfo(id: 'c1', name: 'search'),
      );

      expect(
        parkFinishedOutcome(
          conversation: withCall,
          streaming: const AwaitingText(),
          runId: 'run-0',
        ).runOutcomes,
        hasLength(1),
      );
    });

    test('a run cancelled mid-reply parks, and keeps what it was reasoning',
        () {
      // The pre-delta window: a reply had opened but said nothing. Declining
      // here is what left the run's band with no tile to render on.
      final parked = parkCancelledOutcome(
        conversation: conversation,
        streaming: const TextStreaming(
          messageId: 'm1',
          user: ChatUser.assistant,
          text: '',
          thinkingText: 'weighing it',
        ),
        runId: 'run-0',
      ).runOutcomes['run-0'];

      expect(parked, isNotNull);
      expect(parked!.thinkingText, equals('weighing it'));
    });

    test('parking leaves the messages alone', () {
      final spoken = conversation.withAppendedMessage(
        TextMessage.create(
          id: 'm1',
          user: ChatUser.assistant,
          text: 'Here.',
        ),
      );

      final parked = parkFinishedOutcome(
        conversation: spoken,
        streaming: const AwaitingText(),
        runId: 'run-0',
      );

      expect(parked.messages, equals(spoken.messages));
    });
  });
}
