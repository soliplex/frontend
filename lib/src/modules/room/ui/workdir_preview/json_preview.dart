import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'code_preview.dart';

/// Pretty-prints JSON content and feeds it to [CodePreview] with
/// `language: 'json'` so the existing code-block syntax highlighter
/// handles it. Malformed JSON falls back to the raw bytes — the user
/// still sees something useful even when the file is broken.
class JsonPreview extends StatelessWidget {
  const JsonPreview({super.key, required this.bytes});

  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    final raw = utf8.decode(bytes, allowMalformed: true);
    return CodePreview(
      bytes: Uint8List.fromList(utf8.encode(prettyPrintJsonOrRaw(raw))),
      language: 'json',
    );
  }
}

/// Pretty-prints [raw] as JSON with 2-space indent. Returns [raw]
/// unchanged when it can't be parsed — falls back gracefully so the
/// user still sees something useful for a broken file.
String prettyPrintJsonOrRaw(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return const JsonEncoder.withIndent('  ').convert(decoded);
  } on FormatException {
    return raw;
  }
}
