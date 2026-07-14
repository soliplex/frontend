import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/message_state.dart';
import 'package:soliplex_client/src/domain/source_reference.dart';
import 'package:soliplex_client/src/domain/thread_history.dart';
import 'package:test/test.dart';

void main() {
  group('ThreadHistory', () {
    test('constructs with messages and aguiState', () {
      final messages = [
        TextMessage.create(id: 'm1', user: ChatUser.user, text: 'Hello'),
      ];
      final aguiState = <String, dynamic>{
        'rag': <String, dynamic>{'citations': <dynamic>[]},
      };

      final history = ThreadHistory(messages: messages, aguiState: aguiState);

      expect(history.messages, equals(messages));
      expect(history.aguiState, equals(aguiState));
    });

    test('aguiState defaults to empty map', () {
      final history = ThreadHistory(messages: const []);

      expect(history.aguiState, isEmpty);
    });

    test('is immutable - messages list cannot be modified externally', () {
      final messages = <ChatMessage>[
        TextMessage.create(id: 'm1', user: ChatUser.user, text: 'Hello'),
      ];
      final history = ThreadHistory(messages: messages);

      // Modifying the original list should not affect the history
      messages.add(
        TextMessage.create(id: 'm2', user: ChatUser.user, text: 'World'),
      );

      expect(history.messages, hasLength(1));
    });

    test('is immutable - aguiState cannot be modified externally', () {
      final aguiState = <String, dynamic>{'key': 'value'};
      final history = ThreadHistory(messages: const [], aguiState: aguiState);

      // Modifying the original map should not affect the history
      aguiState['newKey'] = 'newValue';

      expect(history.aguiState.containsKey('newKey'), isFalse);
    });

    test('messageStates defaults to empty map', () {
      final history = ThreadHistory(messages: const []);

      expect(history.messageStates, isEmpty);
    });

    test('constructs with messageStates', () {
      const refs = [
        SourceReference(
          documentId: 'doc-1',
          documentUri: 'https://example.com/doc.pdf',
          content: 'Content',
          chunkId: 'chunk-1',
        ),
      ];
      final state = MessageState(
        userMessageId: 'user-123',
        sourceReferences: refs,
      );

      final history = ThreadHistory(
        messages: const [],
        messageStates: {'user-123': state},
      );

      expect(history.messageStates, hasLength(1));
      expect(history.messageStates['user-123'], state);
    });

    test('is immutable - messageStates cannot be modified externally', () {
      final messageStates = <String, MessageState>{
        'user-1': MessageState(
          userMessageId: 'user-1',
          sourceReferences: const [],
        ),
      };
      final history = ThreadHistory(
        messages: const [],
        messageStates: messageStates,
      );

      // Modifying the original map should not affect the history
      messageStates['user-2'] = MessageState(
        userMessageId: 'user-2',
        sourceReferences: const [],
      );

      expect(history.messageStates.containsKey('user-2'), isFalse);
    });

    test('runs defaults to empty list', () {
      final history = ThreadHistory(messages: const []);

      expect(history.runs, isEmpty);
    });

    test('constructs with runs', () {
      final bundle = RunEventBundle(
        runId: 'run-1',
        events: const [
          TextMessageStartEvent(messageId: 'm1'),
          TextMessageEndEvent(messageId: 'm1'),
        ],
      );

      final history = ThreadHistory(messages: const [], runs: [bundle]);

      expect(history.runs, hasLength(1));
      expect(history.runs[0].runId, 'run-1');
      expect(history.runs[0].events, hasLength(2));
    });

    test('is immutable - runs list cannot be modified externally', () {
      final runs = <RunEventBundle>[
        RunEventBundle(runId: 'run-1', events: const []),
      ];
      final history = ThreadHistory(messages: const [], runs: runs);

      runs.add(RunEventBundle(runId: 'run-2', events: const []));

      expect(history.runs, hasLength(1));
    });

    test('documentFilter defaults to null and carries a provided value', () {
      expect(ThreadHistory(messages: const []).documentFilter, isNull);
      expect(
        ThreadHistory(messages: const [], documentFilter: "id = 'x'")
            .documentFilter,
        equals("id = 'x'"),
      );
    });
  });

  group('RunEventBundle', () {
    test('is immutable - events list cannot be modified externally', () {
      final events = <BaseEvent>[
        const TextMessageStartEvent(messageId: 'm1'),
      ];
      final bundle = RunEventBundle(runId: 'run-1', events: events);

      events.add(const TextMessageEndEvent(messageId: 'm1'));

      expect(bundle.events, hasLength(1));
    });
  });
}
