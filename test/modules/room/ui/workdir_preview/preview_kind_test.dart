import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/preview_kind.dart';

void main() {
  group('detectPreviewKind', () {
    test('maps raster image extensions to image (case-insensitive)', () {
      for (final ext in const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']) {
        expect(detectPreviewKind('photo.$ext'), PreviewKind.image);
        expect(
          detectPreviewKind('photo.${ext.toUpperCase()}'),
          PreviewKind.image,
        );
      }
    });

    test('maps svg to svg', () {
      expect(detectPreviewKind('chart.svg'), PreviewKind.svg);
      expect(detectPreviewKind('chart.SVG'), PreviewKind.svg);
    });

    test('maps markdown extensions to markdown', () {
      expect(detectPreviewKind('README.md'), PreviewKind.markdown);
      expect(detectPreviewKind('NOTES.markdown'), PreviewKind.markdown);
    });

    test('maps common code extensions to code', () {
      for (final ext in const [
        'dart',
        'py',
        'js',
        'ts',
        'tsx',
        'jsx',
        'go',
        'rs',
        'java',
        'kt',
        'swift',
        'c',
        'cpp',
        'h',
        'cs',
        'rb',
        'php',
        'sh',
        'yaml',
        'yml',
        'toml',
        'xml',
        'sql',
      ]) {
        expect(
          detectPreviewKind('file.$ext'),
          PreviewKind.code,
          reason: '$ext should be code',
        );
      }
    });

    test('maps html/htm to html', () {
      expect(detectPreviewKind('index.html'), PreviewKind.html);
      expect(detectPreviewKind('index.htm'), PreviewKind.html);
    });

    test('maps json to json', () {
      expect(detectPreviewKind('data.json'), PreviewKind.json);
    });

    test('maps csv/tsv to csv', () {
      expect(detectPreviewKind('report.csv'), PreviewKind.csv);
      expect(detectPreviewKind('report.tsv'), PreviewKind.csv);
    });

    test('maps plain-text extensions to text', () {
      for (final ext in const ['txt', 'log', 'ini', 'cfg', 'conf']) {
        expect(
          detectPreviewKind('file.$ext'),
          PreviewKind.text,
          reason: '$ext should be text',
        );
      }
    });

    test('maps pdf to pdf', () {
      expect(detectPreviewKind('paper.pdf'), PreviewKind.pdf);
    });

    test('returns unknown for unrecognized or missing extensions', () {
      expect(detectPreviewKind('binary'), PreviewKind.unknown);
      expect(detectPreviewKind('archive.tar.gz'), PreviewKind.unknown);
      expect(detectPreviewKind('mystery.xyz'), PreviewKind.unknown);
    });

    test('treats dotfiles (leading dot, no extension) as unknown', () {
      // '.bashrc' has no useful trailing extension to detect — falls back.
      expect(detectPreviewKind('.bashrc'), PreviewKind.unknown);
    });
  });
}
