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
  });

  group('canRender / isText truth table', () {
    // The whole point of the exhaustive switch is to force a deliberate
    // canRender + isText decision per variant. If a future contributor
    // adds an enum case and the analyzer flags the missing arms, this
    // table is where they record the chosen answer.
    const expectations = <PreviewKind, ({bool canRender, bool isText})>{
      PreviewKind.image: (canRender: true, isText: false),
      PreviewKind.svg: (canRender: true, isText: true),
      PreviewKind.markdown: (canRender: true, isText: true),
      PreviewKind.code: (canRender: true, isText: true),
      PreviewKind.text: (canRender: true, isText: true),
      PreviewKind.html: (canRender: true, isText: true),
      PreviewKind.csv: (canRender: true, isText: true),
      PreviewKind.json: (canRender: true, isText: true),
      PreviewKind.pdf: (canRender: false, isText: false),
      PreviewKind.unknown: (canRender: false, isText: false),
    };

    for (final entry in expectations.entries) {
      final kind = entry.key;
      final expected = entry.value;
      test('$kind canRender=${expected.canRender} isText=${expected.isText}',
          () {
        expect(kind.canRender, expected.canRender);
        expect(kind.isText, expected.isText);
      });
    }
  });

  group('languageForFilename', () {
    test('maps code extensions case-insensitively', () {
      expect(languageForFilename('main.dart'), 'dart');
      expect(languageForFilename('script.PY'), 'python');
      expect(languageForFilename('app.ts'), 'typescript');
      expect(languageForFilename('app.tsx'), 'typescript');
      expect(languageForFilename('run.sh'), 'bash');
      expect(languageForFilename('config.yml'), 'yaml');
      expect(languageForFilename('a.toml'), 'ini');
      expect(languageForFilename('a.py'), 'python');
    });

    test('maps svg and json to their own language', () {
      expect(languageForFilename('a.svg'), 'svg');
      expect(languageForFilename('a.JSON'), 'json');
    });

    test('highlights html as xml', () {
      expect(languageForFilename('page.html'), 'xml');
      expect(languageForFilename('a.htm'), 'xml');
    });

    test('renders delimited and text files as plaintext', () {
      for (final name in const [
        'data.csv',
        'a.tsv',
        'a.log',
        'a.txt',
        'a.ini',
        'a.cfg',
        'a.conf',
      ]) {
        expect(languageForFilename(name), 'plaintext', reason: name);
      }
    });

    test('falls back to plaintext for unknown or missing extensions', () {
      expect(languageForFilename('mystery.xyz'), 'plaintext');
      expect(languageForFilename('no-ext'), 'plaintext');
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

    test('returns null for a trailing dot', () {
      expect(extensionOf('notes.'), isNull);
    });

    test('reads only the last segment of a path', () {
      expect(extensionOf('dir/file.TXT'), 'txt');
      expect(extensionOf('dir.v2/Makefile'), isNull);
      expect(extensionOf('dir/.env'), isNull);
    });
  });

  test('opensInViewer: everything the pager renders, and PDFs', () {
    for (final kind in PreviewKind.values) {
      expect(
        kind.opensInViewer,
        kind.canRender || kind == PreviewKind.pdf,
        reason: '$kind',
      );
    }
    expect(PreviewKind.pdf.opensInViewer, isTrue);
    expect(PreviewKind.pdf.canRender, isFalse,
        reason: 'the pager itself still cannot render one');
    expect(PreviewKind.unknown.opensInViewer, isFalse);
  });
}
