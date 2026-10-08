import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:test/test.dart';

void main() {
  group('estimateMessageTokens', () {
    test('a user message costs its text', () {
      expect(
        estimateMessageTokens(UserMessage(id: 'u1', content: 'hello there')),
        estimateDraftTokens('hello there'),
      );
    });

    test('a multimodal user message costs its text and its images', () {
      final message = UserMessage.multimodal(
        id: 'u1',
        parts: [
          const TextInputContent('look at this'),
          const ImageInputContent(
            source: DataSource(value: 'AAAA', mimeType: 'image/png'),
          ),
        ],
      );

      expect(
        estimateMessageTokens(message),
        estimateDraftTokens('look at this', images: 1),
      );
    });

    test('a multimodal user message costs its other media as images', () {
      final message = UserMessage.multimodal(
        id: 'u1',
        parts: [
          const TextInputContent('listen and read'),
          const AudioInputContent(
            source: DataSource(value: 'AAAA', mimeType: 'audio/wav'),
          ),
          const DocumentInputContent(
            source: DataSource(value: 'AAAA', mimeType: 'application/pdf'),
          ),
        ],
      );

      expect(
        estimateMessageTokens(message),
        estimateDraftTokens('listen and read', images: 2),
      );
    });

    test('an assistant message costs its text and its tool calls', () {
      const message = AssistantMessage(
        id: 'a1',
        content: 'Searching.',
        toolCalls: [
          ToolCall(
            id: 'call_0',
            function: FunctionCall(name: 'search', arguments: '{"q":"x"}'),
          ),
        ],
      );

      expect(
        estimateMessageTokens(message),
        estimateDraftTokens('Searching.\nsearch {"q":"x"}'),
      );
    });

    test('a tool result costs its content and its error', () {
      const message = ToolMessage(
        id: 'r1',
        toolCallId: 'call_0',
        content: 'evidence',
        error: 'partial',
      );

      expect(
        estimateMessageTokens(message),
        estimateDraftTokens('evidence\npartial'),
      );
    });
  });

  group('an activity', () {
    test('costs nothing when the backend drops it', () {
      // The app's own activities never reach the model.
      const message = ActivityMessage(
        id: 'act1',
        activityType: 'skill_tool_call',
        activityContent: {'status': 'running', 'detail': 'a long payload'},
      );

      expect(estimateMessageTokens(message), 0);
    });

    test("costs its JSON when it is one of pydantic-ai's own", () {
      const message = ActivityMessage(
        id: 'act1',
        activityType: 'pydantic_ai_compaction',
        activityContent: {'summary': 'what came before'},
      );

      expect(
        estimateMessageTokens(message),
        estimateDraftTokens('{"summary":"what came before"}'),
      );
    });
  });

  test('a transcript costs the sum of its messages', () {
    final messages = [
      UserMessage(id: 'u1', content: 'hello there'),
      const ToolMessage(id: 'r1', toolCallId: 'c', content: 'evidence'),
    ];

    expect(
      estimateTranscriptTokens(messages),
      estimateDraftTokens('hello there') + estimateDraftTokens('evidence'),
    );
  });
}
