import 'dart:math';

const _whitespace = {' ', '\t', '\n', '\r'};

/// Follows JSON text one character at a time, telling which characters are
/// inside a string literal.
class _StringTracker {
  bool _inString = false;
  bool _escaped = false;

  /// Consumes [char], the character after the last one consumed, and returns
  /// whether it is inside a string literal: after its opening quote, up to and
  /// including its closing quote. The opening quote itself is not, so it reads
  /// as any other value would start.
  bool consume(String char) {
    if (!_inString) {
      _inString = char == '"';
      return false;
    }
    if (_escaped) {
      _escaped = false;
    } else if (char == r'\') {
      _escaped = true;
    } else if (char == '"') {
      _inString = false;
    }
    return true;
  }
}

/// The deepest nesting of `[` and `{` in [source] outside string literals: 0
/// with no brackets, 1 for `[]` and `{}`, 2 for `[[1]]`.
///
/// It reads the brackets alone, so it works on any text; for invalid JSON it
/// is the bracket depth it sees.
int jsonNestingDepth(String source) {
  final strings = _StringTracker();
  var depth = 0;
  var deepest = 0;
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (strings.consume(char)) continue;
    if (char == '[' || char == '{') {
      depth++;
      deepest = max(deepest, depth);
    } else if (char == ']' || char == '}') {
      depth--;
    }
  }
  return deepest;
}

/// [source] in the layout `JsonEncoder.withIndent('  ')` uses, with every
/// member, string and literal copied as written, so duplicate keys, escapes
/// and number spellings survive.
///
/// Assumes [source] is valid JSON; other text comes back reflowed, not
/// rejected.
String formatJson(String source) {
  final strings = _StringTracker();
  final out = StringBuffer();
  var depth = 0;
  // Whether the last character written opened a container: a first child
  // then starts a new line, and an immediate close keeps `{}` or `[]`.
  var justOpened = false;
  void newLine() => out
    ..write('\n')
    ..write('  ' * depth);
  for (var i = 0; i < source.length; i++) {
    final char = source[i];
    if (strings.consume(char)) {
      out.write(char);
      continue;
    }
    if (_whitespace.contains(char)) continue;
    final closes = char == '}' || char == ']';
    if (justOpened && !closes) newLine();
    switch (char) {
      case '{' || '[':
        out.write(char);
        depth++;
      case '}' || ']':
        depth--;
        if (!justOpened) newLine();
        out.write(char);
      case ',':
        out.write(',');
        newLine();
      case ':':
        out.write(': ');
      default:
        out.write(char);
    }
    justOpened = char == '{' || char == '[';
  }
  return out.toString();
}
