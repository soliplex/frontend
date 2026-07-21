import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/markdown/flutter_markdown_plus_renderer.dart';
import 'package:soliplex_frontend/src/shared/failed_image.dart';
import 'package:soliplex_frontend/src/shared/zoomable_image.dart';

void main() {
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

    group('link taps', () {
      const channel = MethodChannel('plugins.flutter.io/url_launcher');
      final launchedUrls = <String>[];
      var failNextLaunch = false;

      setUp(() {
        launchedUrls.clear();
        failNextLaunch = false;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'launch') return null;
          if (failNextLaunch) {
            throw PlatformException(code: 'no_handler');
          }
          launchedUrls.add((call.arguments as Map)['url'] as String);
          return true;
        });
      });

      tearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      testWidgets('tapping a link launches its URL', (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FlutterMarkdownPlusRenderer(
                data: '[email me](mailto:someone@example.com)',
              ),
            ),
          ),
        );

        await tester.tap(find.text('email me'));
        await tester.pump();

        expect(launchedUrls, ['mailto:someone@example.com']);
      });

      testWidgets('a link whose launch fails does not throw', (tester) async {
        failNextLaunch = true;

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: FlutterMarkdownPlusRenderer(
                data: '[email me](mailto:someone@example.com)',
              ),
            ),
          ),
        );

        await tester.tap(find.text('email me'));
        await tester.pump();

        expect(tester.takeException(), isNull);
      });

      testWidgets('a provided onLinkTap overrides the default launch',
          (tester) async {
        String? tappedHref;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: FlutterMarkdownPlusRenderer(
                data: '[email me](mailto:someone@example.com)',
                onLinkTap: (href, _) => tappedHref = href,
              ),
            ),
          ),
        );

        await tester.tap(find.text('email me'));
        await tester.pump();

        expect(tappedHref, 'mailto:someone@example.com');
        expect(launchedUrls, isEmpty);
      });
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
        'a data:image that fails to decode synchronously is left inert (no '
        'tap-to-zoom wrapper)', (tester) async {
      // An empty base64 payload is rejected by tryDecodeImageDataUri, so the
      // inline resolves synchronously to a FailedImage. _MaybeZoomableImage must
      // leave it inert — otherwise tapping a broken image would open a dialog
      // around another broken image. This guards the `inline is FailedImage`
      // branch, distinct from the unsupported-scheme branch. The tap wrapper is
      // uniquely identified by its click-cursor MouseRegion (markdown's own
      // selection/scroll gesture detectors use different cursors).
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](data:image/png;base64,)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(FailedImage), findsOneWidget);
      expect(
        find.ancestor(
          of: find.byType(FailedImage),
          matching: find.byWidgetPredicate(
            (w) => w is MouseRegion && w.cursor == SystemMouseCursors.click,
          ),
        ),
        findsNothing,
      );
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

    testWidgets('data:text/plain URI renders the decoded text inline',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![ignored](data:text/plain,Hello%20there)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FailedImage), findsNothing);
      expect(find.text('Hello there'), findsOneWidget);
    });

    testWidgets('data URI with non-image, non-text MIME renders a FailedImage',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](data:application/pdf;base64,AAAA)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FailedImage), findsOneWidget);
    });

    testWidgets('http image is routed through Image.network', (tester) async {
      // Parity proof: the http(s) branch constructs Image.network with a
      // NetworkImage provider rather than falling through to FailedImage.
      // We assert on the provider type on the first frame, before any
      // network attempt resolves — this avoids racing real DNS resolution.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](https://example.invalid/missing.png)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<NetworkImage>());
    });

    testWidgets('file:// URI is routed through Image.file on native',
        (tester) async {
      // Parity proof. The asynchronous file read does not resolve under the
      // test scheduler, so we inspect the ImageProvider on the first frame
      // instead of waiting for errorBuilder.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](file:///nonexistent/path/that/will/not/load.png)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<FileImage>());
    });

    testWidgets('resource: URI is routed through Image.asset', (tester) async {
      // Parity proof — without an explicit assertion on AssetImage, this
      // test would also pass via the unknown-scheme fallback to FailedImage.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![icon](resource:/assets/missing.png)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
    });

    testWidgets(
        'file:// URI with a non-localhost authority hits the UnsupportedError catch',
        (tester) async {
      // `uri.toFilePath()` throws UnsupportedError on non-Windows when the
      // URI has a non-localhost authority. This exercises the synchronous
      // catch in `loadFileImage` (not the async Image.file errorBuilder
      // path). Skipped on Windows because UNC paths are valid there.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](file://host/foo.png)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FailedImage), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    }, skip: Platform.isWindows);

    testWidgets('unknown scheme (e.g. ftp://) renders a FailedImage',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](ftp://example.com/foo.png)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(FailedImage), findsOneWidget);
    });

    // The inline image is laid out at zero size until its bytes decode (which
    // does not happen under the test scheduler), so hit-test taps miss. We
    // invoke the wrapper's onTap directly to exercise the tap wiring.
    VoidCallback imageTapHandler(WidgetTester tester) {
      final gesture = tester.widget<GestureDetector>(
        find
            .ancestor(
              of: find.byType(Image),
              matching: find.byType(GestureDetector),
            )
            .first,
      );
      return gesture.onTap!;
    }

    testWidgets('tapping a valid image opens a zoomable full-size dialog',
        (tester) async {
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

      // Inline render is a plain image, not the zoomable viewer.
      expect(find.byType(ZoomableImage), findsNothing);

      imageTapHandler(tester)();
      await tester.pumpAndSettle();

      // The dialog frames the image in a ZoomableImage.
      expect(find.byType(ZoomableImage), findsOneWidget);
    });

    testWidgets('a provided onImageTap overrides the default zoom dialog',
        (tester) async {
      String? tappedSrc;
      String? tappedAlt;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![the alt](data:image/png;base64,$pngBase64)',
              onImageTap: (src, alt) {
                tappedSrc = src;
                tappedAlt = alt;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      imageTapHandler(tester)();
      await tester.pumpAndSettle();

      expect(tappedSrc, startsWith('data:image/png;base64,'));
      expect(tappedAlt, 'the alt');
      // Host handled it; no default dialog opened.
      expect(find.byType(ZoomableImage), findsNothing);
    });

    testWidgets(
        'an http image is tap-wired for zoom (routing is not data-only)',
        (tester) async {
      // Guards the http branch of _isZoomableImageUri, which is a separate
      // switch from the provider routing in _buildImage. We assert on the
      // first frame (before the network attempt resolves) to avoid racing DNS.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![alt](https://example.invalid/missing.png)',
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // http is a zoomable scheme, so the inline is wrapped for tap-to-zoom;
      // an inert inline would have no GestureDetector ancestor and the helper
      // would throw.
      expect(imageTapHandler(tester), isNotNull);
    });

    testWidgets('a non-image inline (text data URI) is not tap-to-zoom',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: FlutterMarkdownPlusRenderer(
              data: '![ignored](data:text/plain,Hello%20there)',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Hello there'), findsOneWidget);

      // Tapping a non-image must not open the zoom dialog.
      await tester.tap(find.text('Hello there'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(ZoomableImage), findsNothing);
    });
  });
}
