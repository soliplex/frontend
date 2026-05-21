import 'package:flutter/material.dart';

/// What kind of in-app preview a workdir file should render.
///
/// Detection is extension-based — bytes-sniffing isn't worth the latency
/// for an in-chat preview, and the workdir filenames come from agent
/// tools that already carry a meaningful suffix.
enum PreviewKind {
  image,
  svg,
  markdown,
  code,
  text,
  html,
  csv,
  json,
  pdf,
  unknown;

  /// The kind for [filename] based on its extension. Case-insensitive.
  /// `.bashrc` (leading dot, nothing before it) and unrecognized
  /// extensions yield [PreviewKind.unknown].
  static PreviewKind from(String filename) {
    final ext = extensionOf(filename);
    if (ext == null) return PreviewKind.unknown;
    if (_imageExtensions.contains(ext)) return PreviewKind.image;
    if (ext == 'svg') return PreviewKind.svg;
    if (_markdownExtensions.contains(ext)) return PreviewKind.markdown;
    if (_htmlExtensions.contains(ext)) return PreviewKind.html;
    if (ext == 'json') return PreviewKind.json;
    if (_csvExtensions.contains(ext)) return PreviewKind.csv;
    if (ext == 'pdf') return PreviewKind.pdf;
    if (_languageByCodeExtension.containsKey(ext)) return PreviewKind.code;
    if (_textExtensions.contains(ext)) return PreviewKind.text;
    return PreviewKind.unknown;
  }

  /// Whether the in-app pager can render this kind. False for kinds
  /// that fall through to download (pdf — no client-side renderer in
  /// this app; unknown — no useful mapping).
  bool get canRender => switch (this) {
        PreviewKind.image ||
        PreviewKind.svg ||
        PreviewKind.markdown ||
        PreviewKind.code ||
        PreviewKind.text ||
        PreviewKind.html ||
        PreviewKind.csv ||
        PreviewKind.json =>
          true,
        PreviewKind.pdf || PreviewKind.unknown => false,
      };

  /// Whether the renderer for this kind expects a decoded `String`
  /// (true) or raw `Uint8List` bytes (false).
  bool get isText => switch (this) {
        PreviewKind.svg ||
        PreviewKind.markdown ||
        PreviewKind.code ||
        PreviewKind.text ||
        PreviewKind.html ||
        PreviewKind.csv ||
        PreviewKind.json =>
          true,
        PreviewKind.image || PreviewKind.pdf || PreviewKind.unknown => false,
      };

  /// Material icon mapping for the file-row leading position.
  IconData get rowIcon => switch (this) {
        PreviewKind.image => Icons.image_outlined,
        PreviewKind.svg => Icons.image_outlined,
        PreviewKind.markdown => Icons.article_outlined,
        PreviewKind.code => Icons.code,
        PreviewKind.text => Icons.description_outlined,
        PreviewKind.html => Icons.code,
        PreviewKind.csv => Icons.table_chart_outlined,
        PreviewKind.json => Icons.data_object,
        PreviewKind.pdf => Icons.picture_as_pdf_outlined,
        PreviewKind.unknown => Icons.insert_drive_file_outlined,
      };

  /// flutter_highlight language id used by the shared code-block
  /// renderer. For [code], looks up [filename]'s extension; for [html]
  /// and [csv] the language is fixed. Other kinds don't render through
  /// the code-block path — they get 'plaintext' so the getter is total.
  String highlightLanguageFor(String filename) => switch (this) {
        PreviewKind.html => 'xml',
        PreviewKind.csv => 'plaintext',
        PreviewKind.code =>
          _languageByCodeExtension[extensionOf(filename) ?? ''] ?? 'plaintext',
        _ => 'plaintext',
      };
}

/// Lower-cased extension without the leading dot, or `null` when the
/// filename has no usable extension. `.bashrc` (leading dot, nothing
/// before it) yields `null`.
String? extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) return null;
  return filename.substring(dot + 1).toLowerCase();
}

const _imageExtensions = <String>{
  'png',
  'jpg',
  'jpeg',
  'gif',
  'webp',
  'bmp',
};

const _markdownExtensions = <String>{'md', 'markdown'};

const _htmlExtensions = <String>{'html', 'htm'};

const _csvExtensions = <String>{'csv', 'tsv'};

const _textExtensions = <String>{
  'txt',
  'log',
  'ini',
  'cfg',
  'conf',
};

const _languageByCodeExtension = <String, String>{
  'dart': 'dart',
  'py': 'python',
  'js': 'javascript',
  'mjs': 'javascript',
  'cjs': 'javascript',
  'ts': 'typescript',
  'tsx': 'typescript',
  'jsx': 'javascript',
  'go': 'go',
  'rs': 'rust',
  'java': 'java',
  'kt': 'kotlin',
  'kts': 'kotlin',
  'swift': 'swift',
  'c': 'c',
  'cc': 'cpp',
  'cpp': 'cpp',
  'cxx': 'cpp',
  'h': 'c',
  'hh': 'cpp',
  'hpp': 'cpp',
  'cs': 'csharp',
  'rb': 'ruby',
  'php': 'php',
  'sh': 'bash',
  'bash': 'bash',
  'zsh': 'bash',
  'fish': 'bash',
  'ps1': 'powershell',
  'r': 'r',
  'scala': 'scala',
  'lua': 'lua',
  'pl': 'perl',
  'sql': 'sql',
  'yaml': 'yaml',
  'yml': 'yaml',
  'toml': 'ini',
  'xml': 'xml',
  'gradle': 'groovy',
  'groovy': 'groovy',
};
