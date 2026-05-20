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
  unknown,
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

/// Code extensions the syntax highlighter understands. Kept as a flat set;
/// the ext → highlight language id lookup lives in [codeExtensions] so the
/// two stay in sync via that single map.
const _codeExtensions = <String>{
  'dart',
  'py',
  'js',
  'mjs',
  'cjs',
  'ts',
  'tsx',
  'jsx',
  'go',
  'rs',
  'java',
  'kt',
  'kts',
  'swift',
  'c',
  'cc',
  'cpp',
  'cxx',
  'h',
  'hh',
  'hpp',
  'cs',
  'rb',
  'php',
  'sh',
  'bash',
  'zsh',
  'fish',
  'ps1',
  'r',
  'scala',
  'lua',
  'pl',
  'sql',
  'yaml',
  'yml',
  'toml',
  'xml',
  'gradle',
  'groovy',
  'makefile',
  'dockerfile',
};

/// Returns the [PreviewKind] for [filename] based on its extension.
///
/// Case-insensitive. Files with no extension (or only a leading dot,
/// like `.bashrc`) are [PreviewKind.unknown] — the preview row falls
/// back to download-only for those.
PreviewKind detectPreviewKind(String filename) {
  final ext = _extensionOf(filename);
  if (ext == null) return PreviewKind.unknown;

  if (_imageExtensions.contains(ext)) return PreviewKind.image;
  if (ext == 'svg') return PreviewKind.svg;
  if (_markdownExtensions.contains(ext)) return PreviewKind.markdown;
  if (_htmlExtensions.contains(ext)) return PreviewKind.html;
  if (ext == 'json') return PreviewKind.json;
  if (_csvExtensions.contains(ext)) return PreviewKind.csv;
  if (ext == 'pdf') return PreviewKind.pdf;
  if (_codeExtensions.contains(ext)) return PreviewKind.code;
  if (_textExtensions.contains(ext)) return PreviewKind.text;

  return PreviewKind.unknown;
}

/// Lower-cased extension without the leading dot, or `null` when the
/// filename has no usable extension. `.bashrc` (leading dot, nothing
/// before it) yields `null` so it falls through to [PreviewKind.unknown].
String? _extensionOf(String filename) {
  final dot = filename.lastIndexOf('.');
  if (dot <= 0) return null;
  return filename.substring(dot + 1).toLowerCase();
}
