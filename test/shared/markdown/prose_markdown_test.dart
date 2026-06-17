import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/markdown/prose_markdown.dart';

void main() {
  group('ProseMarkdown', () {
    testWidgets('renders a bulleted list and a link', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProseMarkdown(
              data: '- one\n- two\n\n[Terms](https://example.com)',
            ),
          ),
        ),
      );

      expect(find.textContaining('one'), findsWidgets);
      expect(find.text('Terms'), findsOneWidget);
    });

    testWidgets('onLinkTap override receives the tapped href', (tester) async {
      String? tappedHref;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProseMarkdown(
              data: '[Terms](https://example.com/terms)',
              onLinkTap: (href, _) => tappedHref = href,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Terms'));
      await tester.pump();

      expect(tappedHref, 'https://example.com/terms');
    });

    testWidgets('textStyle override reaches the paragraph', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProseMarkdown(
              data: 'plain paragraph',
              textStyle: TextStyle(color: Colors.purple),
            ),
          ),
        ),
      );

      final body = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
      expect(body.styleSheet?.p?.color, Colors.purple);
    });

    testWidgets('does not render LaTeX (no math builder wired)',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProseMarkdown(data: r'mass-energy $E=mc^2$ holds'),
          ),
        ),
      );

      // With no LaTeX inline syntax wired, the delimiters render literally.
      expect(find.textContaining(r'$E=mc^2$'), findsOneWidget);
    });

    group('default link launch', () {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launchedUrls = <String>[];

      setUp(() {
        launchedUrls.clear();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'launch') return null;
          launchedUrls.add((call.arguments as Map)['url'] as String);
          return true;
        });
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      testWidgets('with no override, tapping a link launches it',
          (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: ProseMarkdown(data: '[Terms](https://example.com)'),
            ),
          ),
        );

        await tester.tap(find.text('Terms'));
        await tester.pump();

        expect(launchedUrls, ['https://example.com']);
      });
    });
  });
}
