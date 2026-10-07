import 'dart:convert';

import 'package:soliplex_agent/src/metering/draft_estimator.dart';
import 'package:soliplex_client/soliplex_client.dart'
    show
        ActivityMessage,
        AssistantMessage,
        DeveloperMessage,
        ImageInputContent,
        Message,
        MultimodalContent,
        ReasoningMessage,
        SystemMessage,
        TextContent,
        TextInputContent,
        ToolCall,
        ToolMessage,
        UserMessage;

/// Estimates the tokens [messages] occupy in a request, biased high like
/// [estimateDraftTokens], which each message is estimated with.
int estimateTranscriptTokens(Iterable<Message> messages) {
  var total = 0;
  for (final message in messages) {
    total += estimateMessageTokens(message);
  }
  return total;
}

/// Estimates the tokens one transcript [message] occupies in a request.
///
/// Everything the request carries for it is counted: a tool call's name and
/// arguments, a tool result's content and error, a pydantic-ai activity as
/// the JSON it travels as, and each image at a flat per-image cost.
int estimateMessageTokens(Message message) => switch (message) {
      UserMessage(:final messageContent) => switch (messageContent) {
          TextContent(:final text) => estimateDraftTokens(text),
          MultimodalContent(:final parts) => estimateDraftTokens(
              [
                for (final part in parts)
                  if (part is TextInputContent) part.text,
              ].join('\n'),
              images: parts.whereType<ImageInputContent>().length,
            ),
        },
      AssistantMessage(:final content, :final toolCalls) => estimateDraftTokens(
          [
            if (content != null && content.isNotEmpty) content,
            for (final call in toolCalls ?? const <ToolCall>[])
              '${call.function.name} ${call.function.arguments}',
          ].join('\n'),
        ),
      ToolMessage(:final content, :final error) =>
        estimateDraftTokens(error == null ? content : '$content\n$error'),
      // pydantic-ai's AG-UI adapter turns only its own reserved activity
      // types into model input; every other activity is dropped before the
      // model sees it, so it costs the request nothing.
      ActivityMessage(:final activityType, :final activityContent) =>
        activityType.startsWith('pydantic_ai_')
            ? estimateDraftTokens(jsonEncode(activityContent))
            : 0,
      ReasoningMessage(:final content) => estimateDraftTokens(content ?? ''),
      SystemMessage(:final content) => estimateDraftTokens(content),
      DeveloperMessage(:final content) => estimateDraftTokens(content),
    };
