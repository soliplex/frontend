import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';

void main() {
  group('sanitizeMarkdown', () {
    test('replaces <br/> with newline', () {
      expect(sanitizeMarkdown('line1<br/>line2'), 'line1\nline2');
    });

    test('replaces <br /> (space before slash) with newline', () {
      expect(sanitizeMarkdown('line1<br />line2'), 'line1\nline2');
    });

    test('replaces multiple br tags', () {
      expect(sanitizeMarkdown('a<br/>b<br />c'), 'a\nb\nc');
    });

    test('returns unchanged string when no br tags present', () {
      expect(sanitizeMarkdown('plain text'), 'plain text');
    });
  });

  group('monospaceFont', () {
    test('returns SF Mono for iOS', () {
      expect(monospaceFont(TargetPlatform.iOS), 'SF Mono');
    });

    test('returns SF Mono for macOS', () {
      expect(monospaceFont(TargetPlatform.macOS), 'SF Mono');
    });

    test('returns Roboto Mono for android', () {
      expect(monospaceFont(TargetPlatform.android), 'Roboto Mono');
    });

    test('returns Roboto Mono for linux', () {
      expect(monospaceFont(TargetPlatform.linux), 'Roboto Mono');
    });

    test('returns Roboto Mono for windows', () {
      expect(monospaceFont(TargetPlatform.windows), 'Roboto Mono');
    });
  });

  group('FlutterMarkdownPlusRenderer widget', () {
    testWidgets('renders markdown text content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(data: 'Hello world'),
          ),
        ),
      );

      expect(find.text('Hello world'), findsOneWidget);
    });

    testWidgets('fires onLinkTap with correct href', (tester) async {
      String? tappedHref;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '[click me](https://example.com)',
              onLinkTap: (href, title) {
                tappedHref = href;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('click me'));
      await tester.pump();

      expect(tappedHref, 'https://example.com');
    });
  });
}
