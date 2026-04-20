import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/source_references_resolver.dart';

final _time = DateTime(2026);

SourceReference _ref({required int index, String? chunkId}) => SourceReference(
  documentId: 'doc-$index',
  documentUri: 'file://doc-$index.pdf',
  content: 'Content $index',
  chunkId: chunkId ?? 'chunk-$index',
  index: index,
);

void main() {
  test('assigns citations to assistant text message', () {
    final refs = [_ref(index: 1)];
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Hello',
      ),
      TextMessage(
        id: 'asst-1',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'Hi there',
      ),
    ];
    final messageStates = {
      'user-1': MessageState(userMessageId: 'user-1', sourceReferences: refs),
    };

    final map = buildSourceReferencesMap(messages, messageStates);
    expect(map['asst-1'], refs);
    expect(map.containsKey('user-1'), isFalse);
  });

  test('assigns citations to last assistant text message in turn', () {
    final refs = [_ref(index: 1), _ref(index: 2)];
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Question',
      ),
      TextMessage(
        id: 'asst-1',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'First response',
      ),
      ToolCallMessage(id: 'tool-1', createdAt: _time, toolCalls: const []),
      TextMessage(
        id: 'asst-2',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'Second response',
      ),
    ];
    final messageStates = {
      'user-1': MessageState(userMessageId: 'user-1', sourceReferences: refs),
    };

    final map = buildSourceReferencesMap(messages, messageStates);
    expect(map.containsKey('asst-1'), isFalse);
    expect(map['asst-2'], refs);
  });

  test('skips tool call messages for citation assignment', () {
    final refs = [_ref(index: 1)];
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Question',
      ),
      ToolCallMessage(id: 'tool-1', createdAt: _time, toolCalls: const []),
      TextMessage(
        id: 'asst-1',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'Answer',
      ),
    ];
    final messageStates = {
      'user-1': MessageState(userMessageId: 'user-1', sourceReferences: refs),
    };

    final map = buildSourceReferencesMap(messages, messageStates);
    expect(map['asst-1'], refs);
  });

  test('handles multiple turns independently', () {
    final refs1 = [_ref(index: 1)];
    final refs2 = [_ref(index: 2), _ref(index: 3)];
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Q1',
      ),
      TextMessage(
        id: 'asst-1',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'A1',
      ),
      TextMessage(
        id: 'user-2',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Q2',
      ),
      TextMessage(
        id: 'asst-2',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'A2',
      ),
    ];
    final messageStates = {
      'user-1': MessageState(userMessageId: 'user-1', sourceReferences: refs1),
      'user-2': MessageState(userMessageId: 'user-2', sourceReferences: refs2),
    };

    final map = buildSourceReferencesMap(messages, messageStates);
    expect(map['asst-1'], refs1);
    expect(map['asst-2'], refs2);
  });

  test('failed user message followed by retry', () {
    final refs = [_ref(index: 1)];
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Q1 (failed)',
      ),
      TextMessage(
        id: 'user-2',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Q1 retry',
      ),
      TextMessage(
        id: 'asst-1',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'A1',
      ),
    ];
    final messageStates = {
      'user-2': MessageState(userMessageId: 'user-2', sourceReferences: refs),
    };

    final map = buildSourceReferencesMap(messages, messageStates);
    expect(map['asst-1'], refs);
  });

  test('no user messages returns empty map', () {
    final messages = <ChatMessage>[
      TextMessage(
        id: 'asst-1',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'Welcome',
      ),
    ];

    final map = buildSourceReferencesMap(messages, const {});
    expect(map, isEmpty);
  });

  test('user message with only tool calls gets no citations displayed', () {
    final refs = [_ref(index: 1)];
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Do something',
      ),
      ToolCallMessage(id: 'tool-1', createdAt: _time, toolCalls: const []),
    ];
    final messageStates = {
      'user-1': MessageState(userMessageId: 'user-1', sourceReferences: refs),
    };

    final map = buildSourceReferencesMap(messages, messageStates);
    expect(map, isEmpty);
  });

  test('empty sourceReferences are not included in map', () {
    final messages = <ChatMessage>[
      TextMessage(
        id: 'user-1',
        user: ChatUser.user,
        createdAt: _time,
        text: 'Hello',
      ),
      TextMessage(
        id: 'asst-1',
        user: ChatUser.assistant,
        createdAt: _time,
        text: 'Hi',
      ),
    ];
    final messageStates = {
      'user-1': MessageState(
        userMessageId: 'user-1',
        sourceReferences: const [],
      ),
    };

    final map = buildSourceReferencesMap(messages, messageStates);
    expect(map, isEmpty);
  });
}
