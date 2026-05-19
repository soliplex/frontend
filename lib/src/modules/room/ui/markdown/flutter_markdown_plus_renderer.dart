import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/failed_image.dart';
import 'code_block_builder.dart';
import 'data_uri_image.dart';
import 'file_image_loader.dart'
    if (dart.library.io) 'file_image_loader_io.dart';
import 'inline_code_builder.dart';
import 'log_source.dart';
import 'markdown_renderer.dart';
import 'markdown_theme_extension.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.markdown_image');

final _brTag = RegExp(r'<br\s*/?>');

String sanitizeMarkdown(String markdown) => markdown.replaceAll(_brTag, '\n');

// Duplicated from lib/src/design/tokens/typography_x.dart so we can hand a
// bare TextStyle (not BuildContext-derived) to MarkdownStyleSheet. Keep in
// sync with appMonospaceTextStyle.
String monospaceFont(TargetPlatform platform) {
  final isApple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  return isApple ? 'SF Mono' : 'Roboto Mono';
}

class FlutterMarkdownPlusRenderer extends MarkdownRenderer {
  const FlutterMarkdownPlusRenderer({
    required super.data,
    super.onLinkTap,
    super.onImageTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final markdownTheme = Theme.of(context).extension<MarkdownThemeExtension>();
    final monoStyle = TextStyle(
      fontFamily: monospaceFont(Theme.of(context).platform),
      fontFamilyFallback: const ['monospace'],
    );

    return MarkdownBody(
      data: sanitizeMarkdown(data),
      selectable: true,
      styleSheet: markdownTheme?.toMarkdownStyleSheet(
        codeFontStyle: monoStyle,
      ),
      blockSyntaxes: [LatexBlockSyntax()],
      inlineSyntaxes: [LatexInlineSyntax()],
      onTapLink: onLinkTap == null
          ? null
          : (_, href, title) {
              if (href != null) onLinkTap!(href, title);
            },
      imageBuilder: _buildImage,
      builders: {
        'code': InlineCodeBuilder(),
        'pre': CodeBlockBuilder(
          // Exception: 14pt sits between bodySmall (13) and bodyMedium (16);
          // chosen so block code reads at roughly the size of surrounding
          // prose without dominating it.
          preferredStyle: monoStyle.copyWith(fontSize: 14),
        ),
        'latex': LatexElementBuilder(),
      },
    );
  }
}

/// Renders the image schemes that `flutter_markdown_plus` markdown can emit:
/// `data:` (image/* and text/*), `http(s):`, `resource:`, and `file:`. All
/// decode or load failures route to a visible [FailedImage] with a source
/// toggle so the failure cause is inspectable. The `file:` branch is
/// conditional-imported (`Image.file` on native, [FailedImage] stub on web).
Widget _buildImage(Uri uri, String? title, String? alt) {
  final rawUri = uri.toString();
  return switch (uri.scheme) {
    'data' => _buildDataImage(uri, alt, rawUri),
    'http' || 'https' => Image.network(
        rawUri,
        errorBuilder: (_, error, stack) {
          logFailedSourceOnce(
            _logger,
            'http image failed to load: ${safeSourceForLog(rawUri)}',
            rawUri,
            error: error,
            stackTrace: stack,
          );
          return FailedImage(source: rawUri, label: alt);
        },
      ),
    'resource' => Image.asset(
        uri.path,
        errorBuilder: (_, error, stack) {
          logFailedSourceOnce(
            _logger,
            'resource image failed to load: ${safeSourceForLog(rawUri)}',
            rawUri,
            error: error,
            stackTrace: stack,
          );
          return FailedImage(source: rawUri, label: alt);
        },
      ),
    'file' => loadFileImage(uri, rawUri, alt),
    _ => _unsupportedSchemeFallback(uri, rawUri, alt),
  };
}

Widget _unsupportedSchemeFallback(Uri uri, String rawUri, String? alt) {
  logFailedSourceOnce(
    _logger,
    'markdown image with unsupported scheme: ${uri.scheme}',
    'scheme:${uri.scheme}',
  );
  return FailedImage(source: rawUri, label: alt);
}

Widget _buildDataImage(Uri uri, String? alt, String rawUri) {
  // `uri.data` is structurally non-null for parsed `data:` URIs (Uri.parse
  // rejects malformed ones), but we keep the null-guard rather than force-
  // unwrap so the type system carries the non-null promise into the body.
  final data = uri.data;
  if (data == null) return FailedImage(source: rawUri, label: alt);

  final mime = data.mimeType;
  if (mime.startsWith('image/')) {
    final decoded = tryDecodeImageDataUri(rawUri);
    if (decoded == null) {
      logFailedSourceOnce(
        _logger,
        'data:image/* URI failed to decode: ${safeSourceForLog(rawUri)}',
        rawUri,
      );
      return FailedImage(source: rawUri, label: alt);
    }
    return Image.memory(
      decoded.bytes,
      errorBuilder: (_, error, stack) {
        logFailedSourceOnce(
          _logger,
          'data:image/* bytes failed to render: ${safeSourceForLog(rawUri)}',
          rawUri,
          error: error,
          stackTrace: stack,
        );
        return FailedImage(source: rawUri, label: alt);
      },
    );
  }

  if (mime.startsWith('text/')) {
    try {
      return Text(data.contentAsString());
    } on FormatException catch (error, stack) {
      logFailedSourceOnce(
        _logger,
        'data:text/* URI failed to decode: ${safeSourceForLog(rawUri)}',
        rawUri,
        error: error,
        stackTrace: stack,
      );
      return FailedImage(source: rawUri, label: alt);
    }
  }

  logFailedSourceOnce(
    _logger,
    'data: URI with unsupported MIME $mime: ${safeSourceForLog(rawUri)}',
    rawUri,
  );
  return FailedImage(source: rawUri, label: alt);
}
