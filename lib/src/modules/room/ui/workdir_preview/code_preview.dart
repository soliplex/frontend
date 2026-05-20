import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../design/design.dart';
import '../markdown/flutter_markdown_plus_renderer.dart';

/// Renders [bytes] as a fenced code block in the shared markdown
/// renderer, so the existing [CodeBlockBuilder] picks it up and
/// applies syntax highlighting, a copy button, and a language label.
class CodePreview extends StatelessWidget {
  const CodePreview({
    super.key,
    required this.bytes,
    required this.language,
  });

  final Uint8List bytes;

  /// `flutter_highlight` language id (e.g. `dart`, `python`, `plaintext`).
  final String language;

  @override
  Widget build(BuildContext context) {
    final content = utf8.decode(bytes, allowMalformed: true);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(SoliplexSpacing.s4),
      child: FlutterMarkdownPlusRenderer(
        data: wrapInCodeFence(content, language),
      ),
    );
  }
}

/// Wraps [content] in a backtick fenced code block tagged with
/// [language]. The fence length grows past any backtick run in
/// [content] so the closing fence can't be eaten by literal backticks
/// in the file (CommonMark §4.5).
String wrapInCodeFence(String content, String language) {
  var longest = 0;
  var current = 0;
  for (var i = 0; i < content.length; i++) {
    if (content.codeUnitAt(i) == 0x60) {
      current++;
      if (current > longest) longest = current;
    } else {
      current = 0;
    }
  }
  final count = longest < 3 ? 3 : longest + 1;
  final fence = ''.padRight(count, '`');
  return '$fence$language\n$content\n$fence';
}
