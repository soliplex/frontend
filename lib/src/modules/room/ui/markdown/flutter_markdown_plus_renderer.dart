import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../../shared/failed_image.dart';
import '../../../../shared/markdown/launch_markdown_link.dart';
import '../../../../shared/markdown/markdown_renderer.dart';
import '../../../../shared/markdown/markdown_style_sheet.dart';
import '../../../../shared/markdown/sanitize_markdown.dart';
import '../../../../shared/zoomable_image.dart';
import '../../../../shared/zoomable_view.dart';
import 'code_block_builder.dart';
import 'data_uri_image.dart';
import 'file_image_loader.dart'
    if (dart.library.io) 'file_image_loader_io.dart';
import 'inline_code_builder.dart';
import 'log_source.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.markdown_image');

class FlutterMarkdownPlusRenderer extends MarkdownRenderer {
  const FlutterMarkdownPlusRenderer({
    required super.data,
    super.onLinkTap,
    super.onImageTap,
    super.key,
    this.selectable = true,
  });

  /// Whether the markdown manages its own selection (via `SelectableText`).
  /// Pass `false` when rendered inside a `SelectionArea` so the surrounding
  /// area handles selection — a self-selecting widget nested in a
  /// `SelectionArea` conflicts.
  final bool selectable;

  @override
  Widget build(BuildContext context) {
    final markdownTheme = Theme.of(context).extension<MarkdownThemeExtension>();
    final mono = monospaceFontFamily(Theme.of(context).platform);
    final monoStyle = TextStyle(
      fontFamily: mono.family,
      fontFamilyFallback: mono.fallback,
    );

    return MarkdownBody(
      data: sanitizeMarkdown(data),
      selectable: selectable,
      styleSheet: markdownTheme?.toMarkdownStyleSheet(
        codeFontStyle: monoStyle,
      ),
      extensionSet: md.ExtensionSet.gitHubFlavored,
      blockSyntaxes: [LatexBlockSyntax()],
      inlineSyntaxes: [LatexInlineSyntax()],
      onTapLink: (_, href, title) {
        if (href == null) return;
        final handleTap = onLinkTap;
        if (handleTap != null) {
          handleTap(href, title);
        } else {
          launchMarkdownLink(href);
        }
      },
      imageBuilder: (uri, title, alt) => _MaybeZoomableImage(
        uri: uri,
        alt: alt,
        onImageTap: onImageTap,
        inline: _buildImage(uri, title, alt),
      ),
      builders: {
        'code': InlineCodeBuilder(),
        'pre': CodeBlockBuilder(
          // design-system exception (approved): 14pt sits between bodySmall
          // (13) and bodyMedium (16); chosen so block code reads at roughly
          // the size of surrounding prose without dominating it.
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
        errorBuilder: _loadErrorBuilder(rawUri, alt, 'http'),
      ),
    'resource' => Image.asset(
        uri.path,
        errorBuilder: _loadErrorBuilder(rawUri, alt, 'resource'),
      ),
    'file' => loadFileImage(uri, rawUri, alt),
    _ => _unsupportedSchemeFallback(uri, rawUri, alt),
  };
}

/// Error builder for network/asset image loads: logs the failure once per
/// source, then renders an inspectable [FailedImage]. [scheme] is the label
/// used in the log message (e.g. `'http'`, `'resource'`).
ImageErrorWidgetBuilder _loadErrorBuilder(
  String rawUri,
  String? alt,
  String scheme,
) =>
    (_, error, stack) {
      logFailedSourceOnce(
        _logger,
        '$scheme image failed to load: ${safeSourceForLog(rawUri)}',
        rawUri,
        error: error,
        stackTrace: stack,
      );
      return FailedImage(source: rawUri, label: alt);
    };

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

/// Wraps an inline markdown image so tapping it opens a full-size zoomable
/// view. Inlines we don't open in a zoom view are returned as-is and left
/// inert: content not treated as a zoomable image (`text/` data URIs, which
/// render as [Text], and unsupported schemes — see [_isZoomableImageUri]), and
/// inlines that already resolved synchronously to a [FailedImage]. Image URIs
/// that fail asynchronously (http/https/resource/file) render after this
/// wrapper is built, so they stay tappable and open a dialog around their own
/// failure fallback. When [onImageTap] is provided the host handles the tap
/// instead of the default zoom dialog.
class _MaybeZoomableImage extends StatelessWidget {
  const _MaybeZoomableImage({
    required this.uri,
    required this.alt,
    required this.onImageTap,
    required this.inline,
  });

  final Uri uri;
  final String? alt;
  final MarkdownImageHandler? onImageTap;
  final Widget inline;

  @override
  Widget build(BuildContext context) {
    if (!_isZoomableImageUri(uri) || inline is FailedImage) return inline;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {
          final handler = onImageTap;
          if (handler != null) {
            handler(uri.toString(), alt);
            return;
          }
          final label = alt;
          showZoomableMediaDialog(
            context,
            viewer: _zoomableImageViewerFor(uri),
            caption: label == null || label.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.all(SoliplexSpacing.s2),
                    child: Text(
                      label,
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ),
          );
        },
        child: inline,
      ),
    );
  }
}

/// Whether [uri] resolves to an image we can open in a zoomable view.
bool _isZoomableImageUri(Uri uri) => switch (uri.scheme) {
      'http' || 'https' || 'resource' || 'file' => true,
      'data' => uri.data?.mimeType.startsWith('image/') ?? false,
      _ => false,
    };

/// Builds the full-size, `BoxFit.contain` viewer for [uri] shown in the zoom
/// dialog. Each scheme routes through a viewer that owns its own load failure
/// ([ZoomableImage] / [fileImageZoomViewer]), so a broken image shows a bare
/// centered fallback rather than a broken image under zoom/rotate chrome. The
/// image's caption is supplied separately by the dialog, so the fallbacks are
/// intentionally label-less.
Widget _zoomableImageViewerFor(Uri uri) {
  final rawUri = uri.toString();
  return switch (uri.scheme) {
    'data' => switch (tryDecodeImageDataUri(rawUri)) {
        final decoded? => ZoomableImage(
            bytes: decoded.bytes,
            logSource: safeSourceForLog(rawUri),
            decodeFailureChild: const FailedImage(),
          ),
        _ => _dataDecodeFailure(rawUri),
      },
    'http' || 'https' => ZoomableImage.provider(
        NetworkImage(rawUri),
        logSource: safeSourceForLog(rawUri),
        decodeFailureChild: const FailedImage(),
      ),
    'resource' => ZoomableImage.provider(
        AssetImage(uri.path),
        logSource: safeSourceForLog(rawUri),
        decodeFailureChild: const FailedImage(),
      ),
    'file' => fileImageZoomViewer(uri, rawUri),
    _ => const Center(child: FailedImage()),
  };
}

/// Fallback for a `data:image/*` URI whose payload can't be decoded, mirroring
/// the inline [_buildDataImage] path so the failure is logged even when it is
/// only reached via the zoom dialog.
Widget _dataDecodeFailure(String rawUri) {
  logFailedSourceOnce(
    _logger,
    'data:image/* URI failed to decode: ${safeSourceForLog(rawUri)}',
    rawUri,
  );
  return const Center(child: FailedImage());
}
