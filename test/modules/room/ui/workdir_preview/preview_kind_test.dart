import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/workdir_preview/preview_kind.dart';

void main() {
  group('PreviewKind.from', () {
    test('maps raster image extensions to image (case-insensitive)', () {
      for (final ext in const ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp']) {
        expect(PreviewKind.from('photo.$ext'), PreviewKind.image);
        expect(
          PreviewKind.from('photo.${ext.toUpperCase()}'),
          PreviewKind.image,
        );
      }
    });

    test('maps svg to svg', () {
      expect(PreviewKind.from('chart.svg'), PreviewKind.svg);
      expect(PreviewKind.from('chart.SVG'), PreviewKind.svg);
    });

    test('maps markdown extensions to markdown', () {
      expect(PreviewKind.from('README.md'), PreviewKind.markdown);
      expect(PreviewKind.from('NOTES.markdown'), PreviewKind.markdown);
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
          PreviewKind.from('file.$ext'),
          PreviewKind.code,
          reason: '$ext should be code',
        );
      }
    });

    test('maps html/htm to html', () {
      expect(PreviewKind.from('index.html'), PreviewKind.html);
      expect(PreviewKind.from('index.htm'), PreviewKind.html);
    });

    test('maps json to json', () {
      expect(PreviewKind.from('data.json'), PreviewKind.json);
    });

    test('maps csv/tsv to csv', () {
      expect(PreviewKind.from('report.csv'), PreviewKind.csv);
      expect(PreviewKind.from('report.tsv'), PreviewKind.csv);
    });

    test('maps plain-text extensions to text', () {
      for (final ext in const ['txt', 'log', 'ini', 'cfg', 'conf']) {
        expect(
          PreviewKind.from('file.$ext'),
          PreviewKind.text,
          reason: '$ext should be text',
        );
      }
    });

    test('maps pdf to pdf', () {
      expect(PreviewKind.from('paper.pdf'), PreviewKind.pdf);
    });

    test('returns unknown for unrecognized or missing extensions', () {
      expect(PreviewKind.from('binary'), PreviewKind.unknown);
      expect(PreviewKind.from('archive.tar.gz'), PreviewKind.unknown);
      expect(PreviewKind.from('mystery.xyz'), PreviewKind.unknown);
    });

    test('treats dotfiles (leading dot, no extension) as unknown', () {
      expect(PreviewKind.from('.bashrc'), PreviewKind.unknown);
    });
  });

  group('canRender', () {
    test('false for pdf and unknown', () {
      expect(PreviewKind.pdf.canRender, isFalse);
      expect(PreviewKind.unknown.canRender, isFalse);
    });
  });

  group('highlightLanguageFor', () {
    test('code looks up the extension', () {
      expect(PreviewKind.code.highlightLanguageFor('main.dart'), 'dart');
      expect(PreviewKind.code.highlightLanguageFor('script.PY'), 'python');
      expect(PreviewKind.code.highlightLanguageFor('app.ts'), 'typescript');
      expect(PreviewKind.code.highlightLanguageFor('app.tsx'), 'typescript');
      expect(PreviewKind.code.highlightLanguageFor('run.sh'), 'bash');
      expect(PreviewKind.code.highlightLanguageFor('config.yml'), 'yaml');
    });

    test('code falls back to plaintext when extension is unknown', () {
      expect(PreviewKind.code.highlightLanguageFor('mystery.xyz'), 'plaintext');
      expect(PreviewKind.code.highlightLanguageFor('no-ext'), 'plaintext');
    });

    test('html is always xml-highlighted', () {
      expect(PreviewKind.html.highlightLanguageFor('page.html'), 'xml');
      expect(PreviewKind.html.highlightLanguageFor('page.htm'), 'xml');
    });

    test('csv is rendered as plaintext (no real csv highlighter)', () {
      expect(PreviewKind.csv.highlightLanguageFor('data.csv'), 'plaintext');
      expect(PreviewKind.csv.highlightLanguageFor('data.tsv'), 'plaintext');
    });
  });

  group('extensionOf', () {
    test('returns the lowercased trailing extension', () {
      expect(extensionOf('photo.PNG'), 'png');
      expect(extensionOf('archive.tar.gz'), 'gz');
    });

    test('returns null for leading-dot dotfiles', () {
      expect(extensionOf('.bashrc'), isNull);
    });

    test('returns null for no-extension filenames', () {
      expect(extensionOf('binary'), isNull);
    });
  });
}
