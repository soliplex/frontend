import 'dart:convert';

/// Result of parsing an LLM response for tool calls.
sealed class ToolCallParseResult {
  const ToolCallParseResult();
}

/// Pure text response — no tool call detected.
class TextResponse extends ToolCallParseResult {
  const TextResponse(this.text);

  /// The full response text.
  final String text;
}

/// Tool call with optional prefix text before it.
class ToolCallResponse extends ToolCallParseResult {
  const ToolCallResponse({
    required this.name,
    required this.arguments,
    this.prefixText = '',
  });

  /// Text before the tool call block (may be empty).
  final String prefixText;

  /// Tool name to invoke.
  final String name;

  /// Tool arguments as a JSON-decoded map.
  final Map<String, dynamic> arguments;
}

/// Fenced code block pattern: ```tool_call\n...\n```
final _toolCallPattern = RegExp(r'```tool_call\s*\n([\s\S]*?)\n\s*```');

/// Parses an LLM text response for tool call blocks.
///
/// Looks for fenced code blocks with the `tool_call` language tag.
/// The expected format is a triple-backtick block tagged `tool_call`
/// containing JSON with `name` and `arguments` fields.
///
/// Returns [ToolCallResponse] if a valid tool call is found,
/// [TextResponse] otherwise. Only the first tool call block is parsed
/// (Phase 1 limitation — Phase 2 adds multi-tool support via native
/// SDK tool calling).
ToolCallParseResult parseToolCallResponse(String response) {
  final match = _toolCallPattern.firstMatch(response);
  if (match == null) return TextResponse(response);

  final jsonStr = match.group(1)!.trim();
  final prefixText = response.substring(0, match.start).trimRight();

  try {
    final decoded = jsonDecode(jsonStr);

    // Handle array edge case: LLMs sometimes wrap in [...].
    final Map<String, dynamic> obj;
    if (decoded is List) {
      if (decoded.isEmpty) return TextResponse(response);
      obj = decoded.first as Map<String, dynamic>;
    } else if (decoded is Map<String, dynamic>) {
      obj = decoded;
    } else {
      return TextResponse(response);
    }

    final name = obj['name'] as String?;
    final args = obj['arguments'];
    if (name == null || name.isEmpty) return TextResponse(response);

    final argsMap = switch (args) {
      Map<String, dynamic>() => args,
      Map() => Map<String, dynamic>.from(args),
      _ => <String, dynamic>{},
    };

    return ToolCallResponse(
      name: name,
      arguments: argsMap,
      prefixText: prefixText,
    );
  } on Object {
    return TextResponse(response);
  }
}
