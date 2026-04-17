import 'package:ag_ui/ag_ui.dart';
import 'package:soliplex_client/src/application/agui_event_processor.dart';
import 'package:soliplex_client/src/application/streaming_state.dart'
    as app_streaming;
import 'package:soliplex_client/src/domain/chat_message.dart';
import 'package:soliplex_client/src/domain/conversation.dart';
import 'package:test/test.dart';

const _defaultUser = ChatUser.assistant;

void main() {
  group('processEvent', () {
    late Conversation conversation;
    late app_streaming.StreamingState streaming;

    setUp(() {
      conversation = Conversation.empty(threadId: 'thread-1');
      streaming = const app_streaming.AwaitingText();
    });

    group('run lifecycle events', () {
      test('RunStartedEvent sets status to Running', () {
        const event = RunStartedEvent(threadId: 'thread-1', runId: 'run-1');

        final result = processEvent(conversation, streaming, event);

        expect(result.conversation.status, isA<Running>());
        expect((result.conversation.status as Running).runId, equals('run-1'));
        expect(result.streaming, isA<app_streaming.AwaitingText>());
      });

      test('RunFinishedEvent sets status to Completed', () {
        final runningConversation = conversation.withStatus(
          const Running(runId: 'run-1'),
        );
        const event = RunFinishedEvent(threadId: 'thread-1', runId: 'run-1');

        final result = processEvent(runningConversation, streaming, event);

        expect(result.conversation.status, isA<Completed>());
        expect(result.streaming, isA<app_streaming.AwaitingText>());
      });

      test('RunErrorEvent sets status to Failed with message', () {
        final runningConversation = conversation.withStatus(
          const Running(runId: 'run-1'),
        );
        const event = RunErrorEvent(
          message: 'Something went wrong',
          code: 'ERROR_CODE',
        );

        final result = processEvent(runningConversation, streaming, event);

        expect(result.conversation.status, isA<Failed>());
        expect(
          (result.conversation.status as Failed).error,
          equals('Something went wrong'),
        );
        expect(result.streaming, isA<app_streaming.AwaitingText>());
      });
    });

    group('text message streaming', () {
      test('TextMessageStartEvent begins streaming', () {
        const event = TextMessageStartEvent(messageId: 'msg-1');

        final result = processEvent(conversation, streaming, event);

        expect(result.streaming, isA<app_streaming.TextStreaming>());
        final streamingState = result.streaming as app_streaming.TextStreaming;
        expect(streamingState.messageId, equals('msg-1'));
        expect(streamingState.text, isEmpty);
      });

      test('TextMessageContentEvent is ignored when AwaitingText', () {
        const event = TextMessageContentEvent(
          messageId: 'msg-1',
          delta: 'Hello',
        );

        final result = processEvent(conversation, streaming, event);

        expect(result.streaming, isA<app_streaming.AwaitingText>());
        expect(result.conversation.messages, isEmpty);
      });

      test('TextMessageContentEvent appends delta to streaming text', () {
        const streamingState = app_streaming.TextStreaming(
          messageId: 'msg-1',
          user: _defaultUser,
          text: 'Hello',
        );
        const event = TextMessageContentEvent(
          messageId: 'msg-1',
          delta: ' world',
        );

        final result = processEvent(conversation, streamingState, event);

        expect(result.streaming, isA<app_streaming.TextStreaming>());
        final newStreaming = result.streaming as app_streaming.TextStreaming;
        expect(newStreaming.messageId, equals('msg-1'));
        expect(newStreaming.text, equals('Hello world'));
      });

      test(
        'TextMessageContentEvent ignores delta if messageId does not match',
        () {
          const streamingState = app_streaming.TextStreaming(
            messageId: 'msg-1',
            user: _defaultUser,
            text: 'Hello',
          );
          const event = TextMessageContentEvent(
            messageId: 'msg-other',
            delta: ' world',
          );

          final result = processEvent(conversation, streamingState, event);

          expect(result.streaming, equals(streamingState));
        },
      );

      test('TextMessageEndEvent finalizes message and resets streaming', () {
        const streamingState = app_streaming.TextStreaming(
          messageId: 'msg-1',
          user: _defaultUser,
          text: 'Hello world',
        );
        const event = TextMessageEndEvent(messageId: 'msg-1');

        final result = processEvent(conversation, streamingState, event);

        expect(result.streaming, isA<app_streaming.AwaitingText>());
        expect(result.conversation.messages, hasLength(1));
        final message = result.conversation.messages.first;
        expect(message.id, equals('msg-1'));
      });

      test('TextMessageEndEvent preserves user role from streaming state', () {
        // Verify role propagation: user from streaming state goes into message
        const streamingState = app_streaming.TextStreaming(
          messageId: 'msg-1',
          user: ChatUser.user, // User role, not assistant
          text: 'User message',
        );
        const event = TextMessageEndEvent(messageId: 'msg-1');

        final result = processEvent(conversation, streamingState, event);

        final message = result.conversation.messages.first;
        expect(message.user, equals(ChatUser.user));
      });

      test(
        'TextMessageEndEvent ignores if messageId does not match streaming',
        () {
          const streamingState = app_streaming.TextStreaming(
            messageId: 'msg-1',
            user: _defaultUser,
            text: 'Hello',
          );
          const event = TextMessageEndEvent(messageId: 'msg-other');

          final result = processEvent(conversation, streamingState, event);

          expect(result.streaming, equals(streamingState));
          expect(result.conversation.messages, isEmpty);
        },
      );

      // Regression: https://github.com/soliplex/frontend/issues/33
      test('TextMessageEndEvent skips duplicate message ID', () {
        // Simulate a conversation that already contains msg-1
        final existing = TextMessage.create(
          id: 'msg-1',
          user: ChatUser.user,
          text: 'original',
        );
        final conversationWithMsg = conversation.withAppendedMessage(existing);

        // Stream a duplicate msg-1
        const streamingState = app_streaming.TextStreaming(
          messageId: 'msg-1',
          user: ChatUser.user,
          text: 'duplicate',
        );
        const event = TextMessageEndEvent(messageId: 'msg-1');

        final result = processEvent(
          conversationWithMsg,
          streamingState,
          event,
        );

        // Should skip — conversation still has exactly 1 message
        expect(result.conversation.messages, hasLength(1));
        expect(
          (result.conversation.messages.first as TextMessage).text,
          equals('original'),
        );
        // Streaming should still reset to AwaitingText
        expect(result.streaming, isA<app_streaming.AwaitingText>());
      });

      test('TextMessageStartEvent maps user role to ChatUser.user', () {
        const event = TextMessageStartEvent(
          messageId: 'msg-1',
          role: TextMessageRole.user,
        );

        final result = processEvent(conversation, streaming, event);

        final streamingState = result.streaming as app_streaming.TextStreaming;
        expect(streamingState.user, equals(ChatUser.user));
      });

      test('TextMessageStartEvent maps system role to ChatUser.system', () {
        const event = TextMessageStartEvent(
          messageId: 'msg-1',
          role: TextMessageRole.system,
        );

        final result = processEvent(conversation, streaming, event);

        final streamingState = result.streaming as app_streaming.TextStreaming;
        expect(streamingState.user, equals(ChatUser.system));
      });

      test('TextMessageStartEvent maps developer role to ChatUser.system', () {
        const event = TextMessageStartEvent(
          messageId: 'msg-1',
          role: TextMessageRole.developer,
        );

        final result = processEvent(conversation, streaming, event);

        final streamingState = result.streaming as app_streaming.TextStreaming;
        expect(streamingState.user, equals(ChatUser.system));
      });
    });

    group('tool call events', () {
      group('ToolCallStart status', () {
        test('creates ToolCallInfo with status streaming', () {
          const event = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );

          final result = processEvent(conversation, streaming, event);

          expect(result.conversation.toolCalls, hasLength(1));
          final tc = result.conversation.toolCalls.first;
          expect(tc.id, equals('tc-1'));
          expect(tc.name, equals('search'));
          expect(tc.status, equals(ToolCallStatus.streaming));
        });

        test('accumulates tool names in activity across multiple starts', () {
          const event1 = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          final result1 = processEvent(conversation, streaming, event1);

          const event2 = ToolCallStartEvent(
            toolCallId: 'tc-2',
            toolCallName: 'summarize',
          );
          final result2 = processEvent(
            result1.conversation,
            result1.streaming,
            event2,
          );

          final awaitingText = result2.streaming as app_streaming.AwaitingText;
          final activity =
              awaitingText.currentActivity as app_streaming.ToolCallActivity;
          expect(activity.allToolNames, equals({'search', 'summarize'}));
        });
      });

      group('ToolCallArgs accumulation', () {
        test('single delta fills arguments', () {
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          final afterStart = processEvent(conversation, streaming, startEvent);

          const argsEvent = ToolCallArgsEvent(
            toolCallId: 'tc-1',
            delta: '{"q":"test"}',
          );
          final result = processEvent(
            afterStart.conversation,
            afterStart.streaming,
            argsEvent,
          );

          expect(
            result.conversation.toolCalls.first.arguments,
            equals('{"q":"test"}'),
          );
        });

        test('multiple deltas concatenate', () {
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          final afterStart = processEvent(conversation, streaming, startEvent);

          const args1 = ToolCallArgsEvent(toolCallId: 'tc-1', delta: '{"q":');
          final afterArgs1 = processEvent(
            afterStart.conversation,
            afterStart.streaming,
            args1,
          );

          const args2 = ToolCallArgsEvent(
            toolCallId: 'tc-1',
            delta: ' "test"}',
          );
          final result = processEvent(
            afterArgs1.conversation,
            afterArgs1.streaming,
            args2,
          );

          expect(
            result.conversation.toolCalls.first.arguments,
            equals('{"q": "test"}'),
          );
        });

        test('zero-arg tool has empty arguments', () {
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'get_time',
          );
          final afterStart = processEvent(conversation, streaming, startEvent);

          // No ToolCallArgsEvent — go straight to end
          const endEvent = ToolCallEndEvent(toolCallId: 'tc-1');
          final result = processEvent(
            afterStart.conversation,
            afterStart.streaming,
            endEvent,
          );

          expect(result.conversation.toolCalls.first.arguments, isEmpty);
        });

        test('args for non-existent toolCallId are ignored', () {
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          final afterStart = processEvent(conversation, streaming, startEvent);

          const argsEvent = ToolCallArgsEvent(
            toolCallId: 'tc-nonexistent',
            delta: '{"q":"test"}',
          );
          final result = processEvent(
            afterStart.conversation,
            afterStart.streaming,
            argsEvent,
          );

          // tc-1's arguments remain empty
          expect(result.conversation.toolCalls.first.arguments, isEmpty);
        });

        test('args after ToolCallEnd are ignored (status guard)', () {
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          var result = processEvent(conversation, streaming, startEvent);

          const argsEvent = ToolCallArgsEvent(
            toolCallId: 'tc-1',
            delta: '{"q":"test"}',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            argsEvent,
          );

          const endEvent = ToolCallEndEvent(toolCallId: 'tc-1');
          result = processEvent(
            result.conversation,
            result.streaming,
            endEvent,
          );

          // Late args after end — should be ignored
          const lateArgs = ToolCallArgsEvent(
            toolCallId: 'tc-1',
            delta: ', "extra":"junk"}',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            lateArgs,
          );

          // Arguments unchanged from before end
          expect(
            result.conversation.toolCalls.first.arguments,
            equals('{"q":"test"}'),
          );
          expect(
            result.conversation.toolCalls.first.status,
            equals(ToolCallStatus.pending),
          );
        });
      });

      group('ToolCallEnd status transition', () {
        test('transitions from streaming to pending', () {
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          final afterStart = processEvent(conversation, streaming, startEvent);

          const argsEvent = ToolCallArgsEvent(
            toolCallId: 'tc-1',
            delta: '{"q":"test"}',
          );
          final afterArgs = processEvent(
            afterStart.conversation,
            afterStart.streaming,
            argsEvent,
          );

          const endEvent = ToolCallEndEvent(toolCallId: 'tc-1');
          final result = processEvent(
            afterArgs.conversation,
            afterArgs.streaming,
            endEvent,
          );

          expect(result.conversation.toolCalls, hasLength(1));
          final tc = result.conversation.toolCalls.first;
          expect(tc.status, equals(ToolCallStatus.pending));
          expect(tc.arguments, equals('{"q":"test"}'));
        });

        test('keeps tool in conversation.toolCalls', () {
          final conversationWithTool = conversation.withToolCall(
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search',
              status: ToolCallStatus.streaming,
            ),
          );
          const event = ToolCallEndEvent(toolCallId: 'tc-1');

          final result = processEvent(conversationWithTool, streaming, event);

          expect(result.conversation.toolCalls, hasLength(1));
          expect(result.conversation.toolCalls.first.id, equals('tc-1'));
        });

        test('does not change activity', () {
          const awaitingWithTool = app_streaming.AwaitingText(
            currentActivity: app_streaming.ToolCallActivity(toolName: 'search'),
          );
          final conversationWithTool = conversation.withToolCall(
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search',
              status: ToolCallStatus.streaming,
            ),
          );
          const event = ToolCallEndEvent(toolCallId: 'tc-1');

          final result = processEvent(
            conversationWithTool,
            awaitingWithTool,
            event,
          );

          expect(
            (result.streaming as app_streaming.AwaitingText).currentActivity,
            isA<app_streaming.ToolCallActivity>(),
          );
        });

        test('duplicate ToolCallEnd does not downgrade status', () {
          // Tool already in pending status (simulating after first end)
          final conversationWithPendingTool = conversation.withToolCall(
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search',
              arguments: '{"q":"test"}',
            ),
          );
          const duplicateEnd = ToolCallEndEvent(toolCallId: 'tc-1');

          final result = processEvent(
            conversationWithPendingTool,
            streaming,
            duplicateEnd,
          );

          // Status should remain pending, not be re-set
          expect(
            result.conversation.toolCalls.first.status,
            equals(ToolCallStatus.pending),
          );
        });

        test('ToolCallEnd does not downgrade executing status', () {
          final conversationWithExecutingTool = conversation.withToolCall(
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search',
              status: ToolCallStatus.executing,
            ),
          );
          const lateEnd = ToolCallEndEvent(toolCallId: 'tc-1');

          final result = processEvent(
            conversationWithExecutingTool,
            streaming,
            lateEnd,
          );

          // Status should remain executing
          expect(
            result.conversation.toolCalls.first.status,
            equals(ToolCallStatus.executing),
          );
        });
      });

      group('multiple tools accumulate independently', () {
        test('two sequential tool calls have correct args and status', () {
          // Start tool A
          const startA = ToolCallStartEvent(
            toolCallId: 'tc-a',
            toolCallName: 'search',
          );
          var result = processEvent(conversation, streaming, startA);

          // Args for tool A
          const argsA = ToolCallArgsEvent(
            toolCallId: 'tc-a',
            delta: '{"q":"alice"}',
          );
          result = processEvent(result.conversation, result.streaming, argsA);

          // End tool A
          const endA = ToolCallEndEvent(toolCallId: 'tc-a');
          result = processEvent(result.conversation, result.streaming, endA);

          // Start tool B
          const startB = ToolCallStartEvent(
            toolCallId: 'tc-b',
            toolCallName: 'summarize',
          );
          result = processEvent(result.conversation, result.streaming, startB);

          // Args for tool B
          const argsB = ToolCallArgsEvent(
            toolCallId: 'tc-b',
            delta: '{"text":"hello"}',
          );
          result = processEvent(result.conversation, result.streaming, argsB);

          // End tool B
          const endB = ToolCallEndEvent(toolCallId: 'tc-b');
          result = processEvent(result.conversation, result.streaming, endB);

          // Both tools present, both pending, correct args
          expect(result.conversation.toolCalls, hasLength(2));

          final toolA = result.conversation.toolCalls.firstWhere(
            (tc) => tc.id == 'tc-a',
          );
          expect(toolA.status, equals(ToolCallStatus.pending));
          expect(toolA.arguments, equals('{"q":"alice"}'));

          final toolB = result.conversation.toolCalls.firstWhere(
            (tc) => tc.id == 'tc-b',
          );
          expect(toolB.status, equals(ToolCallStatus.pending));
          expect(toolB.arguments, equals('{"text":"hello"}'));
        });
      });

      group('ToolCallResult status transition', () {
        test('transitions pending tool to completed with result', () {
          // START → END → RESULT (server-side tool pattern)
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'ask',
          );
          var result = processEvent(conversation, streaming, startEvent);

          const endEvent = ToolCallEndEvent(toolCallId: 'tc-1');
          result = processEvent(
            result.conversation,
            result.streaming,
            endEvent,
          );

          // Tool should be pending after END
          expect(
            result.conversation.toolCalls.first.status,
            equals(ToolCallStatus.pending),
          );

          const resultEvent = ToolCallResultEvent(
            messageId: 'msg-1',
            toolCallId: 'tc-1',
            content: 'The answer is 42',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            resultEvent,
          );

          expect(result.conversation.toolCalls, hasLength(1));
          final tc = result.conversation.toolCalls.first;
          expect(tc.status, equals(ToolCallStatus.completed));
          expect(tc.result, equals('The answer is 42'));
        });

        test('transitions streaming tool to completed (skip END)', () {
          // START → RESULT (no END event)
          const startEvent = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'ask',
          );
          var result = processEvent(conversation, streaming, startEvent);

          // Tool should be streaming after START
          expect(
            result.conversation.toolCalls.first.status,
            equals(ToolCallStatus.streaming),
          );

          const resultEvent = ToolCallResultEvent(
            messageId: 'msg-1',
            toolCallId: 'tc-1',
            content: 'Server result',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            resultEvent,
          );

          expect(result.conversation.toolCalls, hasLength(1));
          final tc = result.conversation.toolCalls.first;
          expect(tc.status, equals(ToolCallStatus.completed));
          expect(tc.result, equals('Server result'));
        });

        test('does not affect already-completed tools', () {
          final conversationWithCompletedTool = conversation.withToolCall(
            const ToolCallInfo(
              id: 'tc-1',
              name: 'search',
              status: ToolCallStatus.completed,
              result: 'original result',
            ),
          );
          const resultEvent = ToolCallResultEvent(
            messageId: 'msg-1',
            toolCallId: 'tc-1',
            content: 'new result',
          );

          final result = processEvent(
            conversationWithCompletedTool,
            streaming,
            resultEvent,
          );

          final tc = result.conversation.toolCalls.first;
          expect(tc.status, equals(ToolCallStatus.completed));
          expect(tc.result, equals('original result'));
        });
      });

      group('ToolCallActivity equality', () {
        test(
            'consecutive starts of same tool produce unequal activities '
            '(different toolCallId)', () {
          const event1 = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'ask',
          );
          final result1 = processEvent(conversation, streaming, event1);

          const event2 = ToolCallStartEvent(
            toolCallId: 'tc-2',
            toolCallName: 'ask',
          );
          final result2 = processEvent(
            result1.conversation,
            result1.streaming,
            event2,
          );

          final activity1 =
              (result1.streaming as app_streaming.AwaitingText).currentActivity;
          final activity2 =
              (result2.streaming as app_streaming.AwaitingText).currentActivity;
          expect(activity1, isNot(equals(activity2)));
        });

        test('ToolCallStartEvent sets latestToolCallId on activity', () {
          const event = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );

          final result = processEvent(conversation, streaming, event);

          final activity = (result.streaming as app_streaming.AwaitingText)
              .currentActivity as app_streaming.ToolCallActivity;
          expect(activity.latestToolCallId, equals('tc-1'));
        });

        test('ToolCallStartEvent sets timestamp on activity', () {
          const event = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
            timestamp: 1000,
          );

          final result = processEvent(conversation, streaming, event);

          final activity = (result.streaming as app_streaming.AwaitingText)
              .currentActivity as app_streaming.ToolCallActivity;
          expect(activity.timestamp, equals(1000));
        });
      });

      group('regression — existing behavior preserved', () {
        test('ToolCallActivity still tracks tool names', () {
          const event = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );

          final result = processEvent(conversation, streaming, event);

          final awaitingText = result.streaming as app_streaming.AwaitingText;
          final activity =
              awaitingText.currentActivity as app_streaming.ToolCallActivity;
          expect(activity.allToolNames, contains('search'));
        });

        test('ToolCallStartEvent during TextStreaming sets activity', () {
          // Start streaming text
          const textStart = TextMessageStartEvent(messageId: 'msg-1');
          var result = processEvent(conversation, streaming, textStart);
          expect(result.streaming, isA<app_streaming.TextStreaming>());

          // Tool call starts while text is streaming
          const toolStart = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            toolStart,
          );

          final textStreaming = result.streaming as app_streaming.TextStreaming;
          final activity =
              textStreaming.currentActivity as app_streaming.ToolCallActivity;
          expect(activity.allToolNames, contains('search'));
          expect(activity.latestToolCallId, equals('tc-1'));
        });

        test('text and tool calls coexist', () {
          // Start text
          const textStart = TextMessageStartEvent(messageId: 'msg-1');
          var result = processEvent(conversation, streaming, textStart);

          // Stream text content
          const textContent = TextMessageContentEvent(
            messageId: 'msg-1',
            delta: 'Here are the results: ',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            textContent,
          );

          // End text
          const textEnd = TextMessageEndEvent(messageId: 'msg-1');
          result = processEvent(result.conversation, result.streaming, textEnd);

          // Then tool call
          const toolStart = ToolCallStartEvent(
            toolCallId: 'tc-1',
            toolCallName: 'search',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            toolStart,
          );

          const toolArgs = ToolCallArgsEvent(
            toolCallId: 'tc-1',
            delta: '{"q":"test"}',
          );
          result = processEvent(
            result.conversation,
            result.streaming,
            toolArgs,
          );

          const toolEnd = ToolCallEndEvent(toolCallId: 'tc-1');
          result = processEvent(result.conversation, result.streaming, toolEnd);

          // Both text message and tool call present
          expect(result.conversation.messages, hasLength(1));
          expect(result.conversation.toolCalls, hasLength(1));
          expect(
            result.conversation.toolCalls.first.status,
            equals(ToolCallStatus.pending),
          );
        });
      });
    });

    group('activity snapshot events', () {
      test('skill_tool_call sets ToolCallActivity with tool name', () {
        const event = ActivitySnapshotEvent(
          messageId: 'msg-1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search'},
        );

        final result = processEvent(conversation, streaming, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        final activity =
            awaitingText.currentActivity as app_streaming.ToolCallActivity;
        expect(activity.allToolNames, contains('search'));
      });

      test('skill_tool_call accumulates on existing ToolCallActivity', () {
        const firstTool = app_streaming.AwaitingText(
          currentActivity: app_streaming.ToolCallActivity(toolName: 'ask'),
        );
        const event = ActivitySnapshotEvent(
          messageId: 'msg-1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search'},
        );

        final result = processEvent(conversation, firstTool, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        final activity =
            awaitingText.currentActivity as app_streaming.ToolCallActivity;
        expect(activity.allToolNames, equals({'ask', 'search'}));
      });

      test('skill_tool_call with missing tool_name passes through', () {
        const event = ActivitySnapshotEvent(
          messageId: 'msg-1',
          activityType: 'skill_tool_call',
          content: <String, dynamic>{},
        );

        final result = processEvent(conversation, streaming, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(
          awaitingText.currentActivity,
          isA<app_streaming.ProcessingActivity>(),
        );
      });

      test('unknown activityType passes through unchanged', () {
        const event = ActivitySnapshotEvent(
          messageId: 'msg-1',
          activityType: 'unknown_activity',
          content: {'data': 'value'},
        );

        final result = processEvent(conversation, streaming, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(
          awaitingText.currentActivity,
          isA<app_streaming.ProcessingActivity>(),
        );
      });

      test('skill_tool_call sets timestamp from event', () {
        const event = ActivitySnapshotEvent(
          messageId: 'msg-1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search'},
          timestamp: 2000,
        );

        final result = processEvent(conversation, streaming, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        final activity =
            awaitingText.currentActivity as app_streaming.ToolCallActivity;
        expect(activity.timestamp, equals(2000));
      });

      test('skill_tool_call without timestamp synthesizes wall-clock value',
          () {
        final before = DateTime.now().millisecondsSinceEpoch;
        const event = ActivitySnapshotEvent(
          messageId: 'msg-1',
          activityType: 'skill_tool_call',
          content: {'tool_name': 'search'},
        );

        final result = processEvent(conversation, streaming, event);
        final after = DateTime.now().millisecondsSinceEpoch;

        final activity = (result.streaming as app_streaming.AwaitingText)
            .currentActivity as app_streaming.ToolCallActivity;
        expect(activity.timestamp, greaterThanOrEqualTo(before));
        expect(activity.timestamp, lessThanOrEqualTo(after));
      });
    });

    group('thinking events', () {
      test('ThinkingStartEvent sets isThinkingStreaming and activity', () {
        const event = ThinkingStartEvent();

        final result = processEvent(conversation, streaming, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(awaitingText.isThinkingStreaming, isTrue);
        expect(
          awaitingText.currentActivity,
          isA<app_streaming.ThinkingActivity>(),
        );
      });

      test('ThinkingEndEvent sets isThinkingStreaming to false', () {
        const thinkingStreaming = app_streaming.AwaitingText(
          isThinkingStreaming: true,
          currentActivity: app_streaming.ThinkingActivity(),
        );
        const event = ThinkingEndEvent();

        final result = processEvent(conversation, thinkingStreaming, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(awaitingText.isThinkingStreaming, isFalse);
      });

      test(
        'ThinkingTextMessageStartEvent sets isThinkingStreaming and activity',
        () {
          const event = ThinkingTextMessageStartEvent();

          final result = processEvent(conversation, streaming, event);

          final awaitingText = result.streaming as app_streaming.AwaitingText;
          expect(awaitingText.isThinkingStreaming, isTrue);
          expect(
            awaitingText.currentActivity,
            isA<app_streaming.ThinkingActivity>(),
          );
        },
      );

      test('ThinkingTextMessageContentEvent buffers text in AwaitingText', () {
        const startedState = app_streaming.AwaitingText(
          isThinkingStreaming: true,
        );
        const event = ThinkingTextMessageContentEvent(delta: 'Thinking...');

        final result = processEvent(conversation, startedState, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(awaitingText.bufferedThinkingText, equals('Thinking...'));
      });

      test('ThinkingTextMessageContentEvent appends to existing buffer', () {
        const startedState = app_streaming.AwaitingText(
          isThinkingStreaming: true,
          bufferedThinkingText: 'Part 1. ',
        );
        const event = ThinkingTextMessageContentEvent(delta: 'Part 2.');

        final result = processEvent(conversation, startedState, event);

        expect(
          (result.streaming as app_streaming.AwaitingText).bufferedThinkingText,
          equals('Part 1. Part 2.'),
        );
      });

      test('ThinkingTextMessageEndEvent sets isThinkingStreaming to false', () {
        const startedState = app_streaming.AwaitingText(
          isThinkingStreaming: true,
          bufferedThinkingText: 'Done thinking',
        );
        const event = ThinkingTextMessageEndEvent();

        final result = processEvent(conversation, startedState, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(awaitingText.isThinkingStreaming, isFalse);
        expect(awaitingText.bufferedThinkingText, equals('Done thinking'));
      });

      test(
        'TextMessageStartEvent transfers buffered thinking to TextStreaming',
        () {
          const awaitingWithThinking = app_streaming.AwaitingText(
            bufferedThinkingText: 'Pre-text thinking',
          );
          const event = TextMessageStartEvent(messageId: 'msg-1');

          final result = processEvent(
            conversation,
            awaitingWithThinking,
            event,
          );

          final textStreaming = result.streaming as app_streaming.TextStreaming;
          expect(textStreaming.thinkingText, equals('Pre-text thinking'));
          expect(textStreaming.text, isEmpty);
        },
      );

      test(
        'ThinkingTextMessageContentEvent appends to TextStreaming.thinkingText',
        () {
          const textStreamingState = app_streaming.TextStreaming(
            messageId: 'msg-1',
            user: _defaultUser,
            text: 'Response text',
            thinkingText: 'Initial thinking',
            isThinkingStreaming: true,
          );
          const event = ThinkingTextMessageContentEvent(
            delta: ' more thinking',
          );

          final result = processEvent(conversation, textStreamingState, event);

          expect(
            (result.streaming as app_streaming.TextStreaming).thinkingText,
            equals('Initial thinking more thinking'),
          );
        },
      );

      test(
        'TextMessageEndEvent preserves thinkingText in finalized message',
        () {
          const streamingState = app_streaming.TextStreaming(
            messageId: 'msg-1',
            user: _defaultUser,
            text: 'Response',
            thinkingText: 'My reasoning',
          );
          const event = TextMessageEndEvent(messageId: 'msg-1');

          final result = processEvent(conversation, streamingState, event);

          final message = result.conversation.messages.first as TextMessage;
          expect(message.thinkingText, equals('My reasoning'));
        },
      );
    });

    group('reasoning events', () {
      test('ReasoningStartEvent sets isThinkingStreaming and activity', () {
        const event = ReasoningStartEvent(messageId: 'reas-1');

        final result = processEvent(conversation, streaming, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(awaitingText.isThinkingStreaming, isTrue);
        expect(
          awaitingText.currentActivity,
          isA<app_streaming.ThinkingActivity>(),
        );
      });

      test('ReasoningEndEvent sets isThinkingStreaming to false', () {
        const reasoningState = app_streaming.AwaitingText(
          isThinkingStreaming: true,
          currentActivity: app_streaming.ThinkingActivity(),
        );
        const event = ReasoningEndEvent(messageId: 'reas-1');

        final result = processEvent(conversation, reasoningState, event);

        final awaitingText = result.streaming as app_streaming.AwaitingText;
        expect(awaitingText.isThinkingStreaming, isFalse);
      });

      test(
        'TextMessageEndEvent preserves reasoning-sourced thinkingText',
        () {
          const event = ReasoningMessageContentEvent(
            messageId: 'reas-1',
            delta: 'Inner reasoning',
          );
          final afterReasoning = processEvent(conversation, streaming, event);

          const textStart = TextMessageStartEvent(messageId: 'msg-1');
          final afterStart = processEvent(
            afterReasoning.conversation,
            afterReasoning.streaming,
            textStart,
          );

          const textEnd = TextMessageEndEvent(messageId: 'msg-1');
          final result = processEvent(
            afterStart.conversation,
            afterStart.streaming,
            textEnd,
          );

          final message = result.conversation.messages.first as TextMessage;
          expect(message.thinkingText, equals('Inner reasoning'));
        },
      );
    });

    group('state events', () {
      test('StateSnapshotEvent replaces aguiState', () {
        const event = StateSnapshotEvent(snapshot: {'key': 'value'});

        final result = processEvent(conversation, streaming, event);

        expect(result.conversation.aguiState, equals({'key': 'value'}));
        expect(result.streaming, equals(streaming));
      });

      test('StateDeltaEvent applies JSON Patch to aguiState', () {
        final conversationWithState = conversation.copyWith(
          aguiState: {'count': 0},
        );
        const event = StateDeltaEvent(
          delta: [
            {'op': 'replace', 'path': '/count', 'value': 1},
            {'op': 'add', 'path': '/name', 'value': 'test'},
          ],
        );

        final result = processEvent(conversationWithState, streaming, event);

        expect(result.conversation.aguiState['count'], 1);
        expect(result.conversation.aguiState['name'], 'test');
      });

      test('StateDeltaEvent applies JSON Patch to empty aguiState', () {
        // Default conversation has empty aguiState
        expect(conversation.aguiState, isEmpty);

        const event = StateDeltaEvent(
          delta: [
            {'op': 'add', 'path': '/count', 'value': 1},
            {
              'op': 'add',
              'path': '/nested',
              'value': {'key': 'value'},
            },
          ],
        );

        final result = processEvent(conversation, streaming, event);

        expect(result.conversation.aguiState['count'], 1);
        expect(result.conversation.aguiState['nested'], {'key': 'value'});
      });
    });

    group('passthrough events', () {
      final passthroughEvents = <String, BaseEvent>{
        'CustomEvent': const CustomEvent(name: 'custom', value: {'data': 123}),
        'TextMessageChunkEvent': const TextMessageChunkEvent(
          messageId: 'msg-1',
          role: TextMessageRole.assistant,
          delta: 'Hello',
        ),
        'ToolCallChunkEvent': const ToolCallChunkEvent(
          toolCallId: 'tc-1',
          toolCallName: 'search',
          delta: '{"q":"test"}',
        ),
        'MessagesSnapshotEvent': const MessagesSnapshotEvent(messages: []),
        'StepStartedEvent': const StepStartedEvent(stepName: 'step-1'),
        'StepFinishedEvent': const StepFinishedEvent(stepName: 'step-1'),
        'RawEvent': const RawEvent(event: 'raw-data'),
        'ThinkingContentEvent': const ThinkingContentEvent(delta: 'hmm'),
      };

      for (final entry in passthroughEvents.entries) {
        test('${entry.key} passes through unchanged', () {
          final result = processEvent(conversation, streaming, entry.value);

          expect(result.conversation, equals(conversation));
          expect(result.streaming, equals(streaming));
        });
      }
    });
  });
}
