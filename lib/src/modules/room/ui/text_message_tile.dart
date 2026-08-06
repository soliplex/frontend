import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../shared/failed_image.dart';
import '../../../shared/zoomable_image.dart';
import '../../../shared/zoomable_view.dart';
import '../execution_tracker.dart';
import 'attachment_pill.dart';
import 'citations_section.dart';
import 'copy_button.dart';
import 'execution/phase_indicator.dart';
import 'execution/execution_timeline.dart';
import 'execution/static_thinking_block.dart';
import 'execution/thinking_block.dart';
import 'feedback_buttons.dart';
import 'markdown/flutter_markdown_plus_renderer.dart';
import 'markdown/log_source.dart';
import 'message_caption.dart';
import 'paged_zoomable_images.dart';
import 'workdir_files_section.dart';
import 'package:soliplex_design/soliplex_design.dart';

final _logger =
    LogManager.instance.getLogger('soliplex_frontend.text_message_tile');

/// Side of an attachment's thumbnail in the row above a message. Sized as a tap
/// target — it is what opens the full-size browser — so it sits at the 48 px
/// platform minimum. A component dimension, off the spacing scale.
const double _attachmentTileSize = 48;

/// Long-edge bound on a tile's *decode*. `BoxFit.cover` in a 48 px box fills
/// from the short edge, which needs
/// `_attachmentTileSize * devicePixelRatio` ≈ 144 px at dpr 3; a 640 long edge
/// clears that for anything narrower than ~40:9. Costs at most ~1.6 MB of RGBA
/// (a square 640×640), against ~48 MB for an unbounded 12 MP photo — and the
/// timeline is a scrolling list, so that cost repeats per image on screen.
const int _inlineDecodeExtent = 640;

/// Long-edge bound on a full-size page's decode in the zoom browser, which
/// `showZoomableMediaDialog` bounds to a fixed max width and a fraction of the
/// viewport height. At fit, that is well inside this on most devices; a tall
/// window at a high pixel ratio can ask for somewhat more, and there the viewer
/// interpolates slightly — which `ZoomableView`'s max scale would make a 12 MP
/// original do anyway.
const int _zoomDecodeExtent = 2560;

const _imageUnavailableLabel = 'Attached image unavailable';

class TextMessageTile extends StatelessWidget {
  const TextMessageTile({
    super.key,
    required this.roomId,
    required this.message,
    this.runId,
    this.sourceReferences,
    this.onFeedbackSubmit,
    this.onInspect,
    this.onShowChunkVisualization,
    this.onFetchWorkdirFiles,
    this.onDownloadWorkdirFile,
    this.onPreviewWorkdirFile,
    this.executionTracker,
    this.streamingPhase,
  });

  final String roomId;
  final TextMessage message;
  final String? runId;
  final List<SourceReference>? sourceReferences;
  final void Function(FeedbackType feedback, String? reason)? onFeedbackSubmit;
  final VoidCallback? onInspect;
  final void Function(SourceReference)? onShowChunkVisualization;
  final FetchWorkdirFiles? onFetchWorkdirFiles;
  final DownloadWorkdirFile? onDownloadWorkdirFile;
  final FetchWorkdirFileBytes? onPreviewWorkdirFile;
  final ExecutionTracker? executionTracker;
  final RunPhase? streamingPhase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.user == ChatUser.user;
    final showFeedback = !isUser && onFeedbackSubmit != null;
    final hasTracker = executionTracker != null;

    return Column(
      crossAxisAlignment:
          isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (streamingPhase != null) PhaseIndicator(phase: streamingPhase!),
        if (hasTracker)
          ExecutionTimeline(
            roomId: roomId,
            messageId: message.id,
            tracker: executionTracker!,
          ),
        if (hasTracker)
          ExecutionThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            tracker: executionTracker!,
          )
        else if (!isUser && message.hasThinkingText)
          StaticThinkingBlock(
            roomId: roomId,
            messageId: message.id,
            text: message.thinkingText,
          ),
        Text(
          isUser ? 'You' : 'Assistant',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: SoliplexSpacing.s1),
        _MessageBubble(message: message),
        if (message.createdAt != null) MessageCaption(time: message.createdAt!),
        const SizedBox(height: SoliplexSpacing.s2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CopyButton(text: message.text),
            if (isUser && onInspect != null) ...[
              const SizedBox(width: SoliplexSpacing.s1),
              Tooltip(
                message: 'Inspect HTTP traffic',
                child: InkWell(
                  onTap: onInspect,
                  borderRadius: BorderRadius.circular(context.radii.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(SoliplexSpacing.s1),
                    child: Icon(
                      Icons.bug_report_outlined,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ],
            if (showFeedback) ...[
              const SizedBox(width: SoliplexSpacing.s1),
              FeedbackButtons(onFeedbackSubmit: onFeedbackSubmit!),
            ],
          ],
        ),
        if (sourceReferences != null && sourceReferences!.isNotEmpty)
          CitationsSection(
            sourceReferences: sourceReferences!,
            onShowChunkVisualization: onShowChunkVisualization,
          ),
        if (!isUser &&
            runId != null &&
            onFetchWorkdirFiles != null &&
            onDownloadWorkdirFile != null)
          WorkdirFilesSection(
            // Force re-mount (and re-fetch) if the assistant message is
            // ever rebuilt with a different runId.
            key: ValueKey(runId),
            runId: runId!,
            fetchFiles: onFetchWorkdirFiles!,
            onDownload: onDownloadWorkdirFile!,
            onPreview: onPreviewWorkdirFile,
          ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final TextMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.user == ChatUser.user;

    // Speech-bubble corners: both top corners and the leading bottom corner
    // are fully rounded; the trailing bottom corner (toward the sender's edge)
    // is tightened to point at its author — bottom-right for the user (right
    // aligned), bottom-left for the assistant (left aligned).
    final rounded = Radius.circular(context.radii.md);
    final tight = Radius.circular(context.radii.sm);
    return Container(
      // design-system exception: 14/10 is the documented chat-bubble padding
      // (see design_system/README.md "the only 14 in the system").
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isUser
            ? theme.colorScheme.primaryContainer
            : theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.only(
          topLeft: rounded,
          topRight: rounded,
          bottomLeft: isUser ? rounded : tight,
          bottomRight: isUser ? tight : rounded,
        ),
      ),
      child: isUser
          ? _userContent(theme)
          : message.text.isEmpty
              ? const SoliplexShimmer(lineFractions: [1, 1, 0.55])
              : FlutterMarkdownPlusRenderer(
                  data: message.text,
                  selectable: false,
                ),
    );
  }

  Widget _userContent(ThemeData theme) {
    final style = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onPrimaryContainer,
    );
    final parts = message.parts;
    if (parts == null) return Text(message.text, style: style);
    return _UserMessageBody(
      messageId: message.id,
      parts: parts,
      style: style,
    );
  }
}

/// One attachment, as the two places it appears: a tile in the row above the
/// text, and a pill at its position in the sentence.
typedef _Slot = ({MessagePart part, int? imageIndex});

/// A user message's ordered parts as a row of attachment tiles over the text
/// that was written around them.
///
/// The tiles are hoisted out of the sentence because a thumbnail is taller than
/// a line of body text, and an inline element contributes its whole height to
/// the line it sits in — so a photo run into a sentence swells one line and
/// breaks the paragraph. A text-scale pill holds each attachment's place
/// instead, which is also what keeps the runs either side of it from becoming
/// adjacent: the text is reproduced exactly as written, with no gap to repair.
///
/// Tiles and pills are both in part order, so the *n*th pill is the *n*th tile.
/// Nothing is numbered — a digit would have to resolve against a badge on the
/// tile to mean anything, and at 48 px a legible badge covers the image it sits
/// on.
///
/// The tile is a tap target rather than a preview; tapping opens the full-size
/// browser, which is what answers "did I attach the right one".
class _UserMessageBody extends StatelessWidget {
  const _UserMessageBody({
    required this.messageId,
    required this.parts,
    this.style,
  });

  final String messageId;
  final List<MessagePart> parts;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    // Slot order is attachment order; `imageIndex` is the pager's, which counts
    // images alone. A missing attachment makes the two diverge.
    final slots = <_Slot>[];
    var imageIndex = 0;
    for (final part in parts) {
      switch (part) {
        case ImagePart():
          slots.add((part: part, imageIndex: imageIndex++));
        case MissingAttachmentPart():
          slots.add((part: part, imageIndex: null));
        case TextPart():
          break;
      }
    }
    final images = parts.whereType<ImagePart>().toList();

    final spans = <InlineSpan>[];
    var slotIndex = 0;
    for (final part in parts) {
      switch (part) {
        case TextPart(:final text):
          // Empty runs are dropped on the way out too, so the bubble does not
          // render a span the model never received.
          if (text.isEmpty) continue;
          spans.add(TextSpan(text: text));
        case ImagePart() || MissingAttachmentPart():
          final slot = slots[slotIndex];
          spans.add(
            _pillSpan(
              _pill(context, slot, slotIndex, slots.length, images),
            ),
          );
          slotIndex++;
      }
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: SoliplexSpacing.s2,
      children: [
        if (slots.isNotEmpty)
          Wrap(
            spacing: SoliplexSpacing.s2,
            runSpacing: SoliplexSpacing.s2,
            children: [
              for (final slot in slots) _tile(context, slot, images),
            ],
          ),
        if (spans.isNotEmpty)
          Text.rich(TextSpan(children: spans), style: style),
      ],
    );
  }

  /// One attachment's tile in the row.
  Widget _tile(BuildContext context, _Slot slot, List<ImagePart> images) {
    final part = slot.part;
    if (part is! ImagePart) {
      return _AttachmentTileUnavailable(
        label: _missingLabel(part as MissingAttachmentPart),
      );
    }
    final index = slot.imageIndex!;
    return _AttachmentTile(
      image: part,
      label: _imageLabel(index, images.length),
      logSource: _imageLogSource(index),
      onTap: () => _openBrowser(context, images, index),
    );
  }

  /// One attachment's pill in the sentence.
  Widget _pill(
    BuildContext context,
    _Slot slot,
    int slotIndex,
    int slotCount,
    List<ImagePart> images,
  ) {
    final part = slot.part;
    // The ordinal is not rendered — order does that job visually — but a screen
    // reader has no row to look at, so it is announced.
    final position = 'Attachment ${slotIndex + 1} of $slotCount';
    if (part is! ImagePart) {
      return AttachmentPill.error(
        icon: Icons.broken_image_outlined,
        description:
            '$position. ${_missingLabel(part as MissingAttachmentPart)}',
      );
    }
    final index = slot.imageIndex!;
    return AttachmentPill(
      icon: Icons.image_outlined,
      description: '$position. ${_imageLabel(index, images.length)}',
      onTap: () => _openBrowser(context, images, index),
    );
  }

  /// Wraps a pill as an inline span.
  ///
  /// Spaced either side so it reads as a word in the sentence rather than
  /// colliding with the glyph beside it — symmetric, which also covers two
  /// attachments written side by side, with no text between them.
  ///
  /// The transcript is wrapped in a SelectionArea. A pill carries no text of the
  /// user's, so it stays out of a drag-selection rather than contributing a gap
  /// to what the user copies.
  InlineSpan _pillSpan(Widget child) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: SelectionContainer.disabled(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
            child: child,
          ),
        ),
      );

  String _imageLabel(int index, int count) =>
      'Attached image ${index + 1} of $count';

  /// Names what is missing rather than only that something is, so a screen
  /// reader distinguishes a broken image from a kind of file this app cannot
  /// show at all.
  String _missingLabel(MissingAttachmentPart part) {
    final type = part.mimeType;
    final subject = type == null ? 'An attachment' : 'An attachment ($type)';
    return switch (part.reason) {
      MissingAttachmentReason.undecodable =>
        '$subject could not be read and is not shown',
      MissingAttachmentReason.unsupportedType =>
        '$subject is a kind this app cannot show',
      MissingAttachmentReason.remoteSource =>
        '$subject is stored elsewhere and is not shown',
    };
  }

  String _imageLogSource(int index) => '$messageId#$index';

  /// Opens every image in the message, starting at the tapped one, in the
  /// app's shared zoom browser — so a photo that arrived sideways can be
  /// rotated and read.
  void _openBrowser(BuildContext context, List<ImagePart> images, int index) {
    showZoomableMediaDialog(
      context,
      viewer: PagedZoomableImages(
        itemCount: images.length,
        initialIndex: index,
        autofocus: true,
        pageBuilder: (context, i, rotation) => ZoomableImage.controlledRotation(
          bytes: images[i].bytes,
          maxDecodeExtent: _zoomDecodeExtent,
          semanticLabel: _imageLabel(i, images.length),
          logSource: _imageLogSource(i),
          rotationQuarterTurns: rotation.quarterTurns,
          onRotate: rotation.onRotate,
          decodeFailureChild: const FailedImage(
            label: _imageUnavailableLabel,
          ),
        ),
      ),
    );
  }
}

/// Stands in for an attachment that cannot be shown, filling the same 48 px
/// slot as a thumbnail so the sentence does not reflow.
///
/// Serves both losses that reach the bubble: an attachment history could not
/// rebuild, and an image whose bytes reached the widget but would not decode.
///
/// Purpose-built rather than [FailedImage], which is sized for the full-size
/// browser: a 96 px icon box over a text label is several times wider than this
/// slot, so fitting it here shrinks the label well past legibility.
///
/// The glyph alone says only that something is missing, and it looks the same
/// whichever loss produced it, so [label] is carried two ways: as the screen
/// reader's announcement, and as a tooltip for everyone else — on hover on a
/// pointer, on long-press on a touch screen. There is no room to render it
/// inline without breaking the sentence the slot sits in.
class _AttachmentTileUnavailable extends StatelessWidget {
  const _AttachmentTileUnavailable({required this.label});

  /// The complete announcement for this slot — what is missing, and which one.
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      image: true,
      child: Tooltip(
        message: label,
        // The Semantics above already announces this; a tooltip that also
        // contributed it would have a screen reader read the slot twice.
        excludeFromSemantics: true,
        child: Container(
          width: _attachmentTileSize,
          height: _attachmentTileSize,
          decoration: BoxDecoration(
            border: Border.all(color: theme.colorScheme.outline),
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(context.radii.sm),
          ),
          child: Icon(
            Icons.broken_image,
            size: 24,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// One attached image, inline in the bubble's text. Tapping opens the full-size
/// browser; a decode failure shows a broken-image fallback in the same slot.
class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.image,
    required this.label,
    required this.logSource,
    required this.onTap,
  });

  final ImagePart image;
  final String label;
  final String logSource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // `sm` rather than the default `md`: at 48 px this is a small hit-target
    // well, where a 12 px radius reads as a lozenge.
    final radius = BorderRadius.circular(context.radii.sm);
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: ClipRRect(
        borderRadius: radius,
        child: Image(
          // `ResizeImagePolicy.fit` bounds the *long* edge, unlike `.exact`,
          // so a tall image is capped too — see `_inlineDecodeExtent`.
          image: ResizeImage(
            MemoryImage(image.bytes),
            width: _inlineDecodeExtent,
            height: _inlineDecodeExtent,
            policy: ResizeImagePolicy.fit,
          ),
          width: _attachmentTileSize,
          height: _attachmentTileSize,
          fit: BoxFit.cover,
          semanticLabel: label,
          errorBuilder: (context, error, stack) {
            logFailedSourceOnce(
              _logger,
              'attached image decode failed: $logSource '
              '(${image.mimeType}, ${image.bytes.length} bytes)',
              logSource,
              error: error,
              stackTrace: stack,
            );
            return _AttachmentTileUnavailable(
              label: '$label — $_imageUnavailableLabel',
            );
          },
        ),
      ),
    );
  }
}
