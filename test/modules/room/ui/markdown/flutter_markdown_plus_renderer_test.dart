import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_frontend/src/shared/failed_image.dart';

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

  group('FlutterMarkdownPlusRenderer image handling', () {
    // 1x1 transparent PNG. Same bytes as data_uri_image_test and
    // chunk_visualization_page_test.
    final pngBytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4'
      '2mP8/58BAwAI/AL+hc2rNAAAAABJRU5ErkJggg==',
    );
    final pngBase64 = base64Encode(pngBytes);

    testWidgets(
        'malformed data URI image renders a FailedImage, not a red error widget',
        (tester) async {
      // Six base64 chars (mod 4 == 2) is the shape of the truncated payload
      // observed in production. Without the custom imageBuilder this throws
      // FormatException out of build() and the whole bubble red-screens.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](data:image/png;base64,AAAAAA)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FailedImage), findsOneWidget);
    });

    testWidgets(
        'broken data URI image toggles to a source view exposing the normalised URI',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](data:image/png;base64,AAAAAA)',
            ),
          ),
        ),
      );
      await tester.pump();

      // Default mode shows the broken-image preview, no raw URI text.
      expect(find.byType(FailedImage), findsOneWidget);
      expect(find.byIcon(Icons.broken_image), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);

      // Toggle to source view.
      await tester.tap(find.byIcon(Icons.code));
      await tester.pump();

      expect(find.byIcon(Icons.broken_image), findsNothing);
      // Uri.toString() normalises truncated base64 by adding `=` padding, so
      // we assert against the normalised form rather than the raw markdown
      // source.
      expect(
        find.text('data:image/png;base64,AAAAAA=='),
        findsOneWidget,
      );
    });

    testWidgets('valid PNG data URI renders an Image widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](data:image/png;base64,$pngBase64)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(Image), findsOneWidget);
      expect(find.byType(FailedImage), findsNothing);
    });
  });
}
