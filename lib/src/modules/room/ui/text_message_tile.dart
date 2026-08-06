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
const int _tileDecodeExtent = 640;

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
    this.attachmentsBefore = 0,
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

  /// Attachment slots in the thread before this message, so its own are
  /// numbered in the thread's sequence rather than from one.
  final int attachmentsBefore;

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
        _MessageBubble(
          message: message,
          attachmentsBefore: attachmentsBefore,
        ),
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
  const _MessageBubble({
    required this.message,
    required this.attachmentsBefore,
  });

  final TextMessage message;
  final int attachmentsBefore;

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
      attachmentsBefore: attachmentsBefore,
      style: style,
    );
  }
}

/// One attachment in a message, carrying the number that names it.
///
/// Sealed rather than a record with a nullable index: "an image has a page in
/// the browser, an unshowable slot does not" is the rule every consumer needs,
/// and a nullable field states it in a way the compiler cannot check — leaving
/// each reader to re-derive it with a cast.
sealed class _Slot {
  const _Slot(this.number);

  /// This attachment's number in the thread — what the badge and the pill show,
  /// and what the model was told to call it.
  final int number;
}

/// An attachment whose bytes are here.
final class _ImageSlot extends _Slot {
  const _ImageSlot(super.number, this.image, this.page);

  final ImagePart image;

  /// Where this image sits in the zoom browser, which pages over decodable
  /// images alone. Not [number]: a slot that cannot be shown takes a number and
  /// no page, so the two diverge from that point on.
  final int page;
}

/// An attachment the message was sent with that cannot be shown.
final class _MissingSlot extends _Slot {
  const _MissingSlot(super.number, this.part);

  final MissingAttachmentPart part;
}

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
/// Every attachment is numbered across the thread and shows that number twice —
/// badged on its tile and carried by its pill — so a reader can name one in
/// conversation. It is the number the model was given for the same image, which
/// is what makes naming it work.
///
/// The tile is a tap target rather than a preview; tapping opens the full-size
/// browser, which is what answers "did I attach the right one".
class _UserMessageBody extends StatelessWidget {
  const _UserMessageBody({
    required this.messageId,
    required this.parts,
    required this.attachmentsBefore,
    this.style,
  });

  final String messageId;
  final List<MessagePart> parts;
  final int attachmentsBefore;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final slots = <_Slot>[];
    var page = 0;
    for (final part in parts) {
      final number = attachmentsBefore + slots.length + 1;
      switch (part) {
        case ImagePart():
          slots.add(_ImageSlot(number, part, page++));
        case MissingAttachmentPart():
          slots.add(_MissingSlot(number, part));
        case TextPart():
          break;
      }
    }
    final imageSlots = slots.whereType<_ImageSlot>().toList();

    var hasText = false;
    final spans = <InlineSpan>[];
    var slotIndex = 0;
    for (final part in parts) {
      switch (part) {
        case TextPart(:final text):
          // Empty runs are dropped on the way out too, so the bubble does not
          // render a span the model never received.
          if (text.isEmpty) continue;
          hasText = true;
          spans.add(TextSpan(text: text));
        case ImagePart() || MissingAttachmentPart():
          spans.add(_pillSpan(_pill(context, slots[slotIndex], imageSlots)));
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
              for (final slot in slots) _tile(context, slot, imageSlots),
            ],
          ),
        // A pill holds an attachment's place in a sentence. With nothing
        // written around them there is no sentence to hold a place in, and a
        // row of pills under the tiles they name would be the same row twice.
        if (hasText) Text.rich(TextSpan(children: spans), style: style),
      ],
    );
  }

  /// One attachment's tile in the row, badged with the number that names it.
  Widget _tile(BuildContext context, _Slot slot, List<_ImageSlot> imageSlots) {
    final tile = switch (slot) {
      _MissingSlot(:final part) =>
        _AttachmentTileUnavailable(label: _missingLabel(part)),
      _ImageSlot(:final image, :final page, :final number) => _AttachmentTile(
          image: image,
          label: 'Image $number',
          logSource: _imageLogSource(page),
          onTap: () => _openBrowser(context, imageSlots, page),
        ),
    };

    return Stack(
      children: [
        tile,
        Positioned(
          top: 0,
          left: 0,
          // A `Stack` hit-tests children in reverse paint order and a
          // `RenderParagraph` always reports a hit, so without this the digits
          // swallow taps that should reach the tile's `InkWell` — a dead patch
          // in a 48 px target, right where the badge draws the eye.
          child: IgnorePointer(
            child: _TileNumber(
              number: slot.number,
              isError: slot is _MissingSlot,
            ),
          ),
        ),
      ],
    );
  }

  /// One attachment's pill in the sentence, carrying the number that names it.
  ///
  /// The same number the model is given, so a user reading "3" here and writing
  /// "what is in image 3" is asking about the image the model knows by that
  /// name.
  Widget _pill(
    BuildContext context,
    _Slot slot,
    List<_ImageSlot> imageSlots,
  ) =>
      switch (slot) {
        // Error-toned so a slot the message was sent with but cannot show is
        // noticed rather than skimmed past — it is small, and the sentence
        // around it reads normally, so nothing else marks it.
        _MissingSlot(:final part, :final number) => AttachmentPill.error(
            icon: Icons.broken_image_outlined,
            label: '$number',
            description: 'Image $number. ${_missingLabel(part)}',
          ),
        _ImageSlot(:final page, :final number) => AttachmentPill(
            icon: Icons.image_outlined,
            label: '$number',
            description: 'Image $number',
            onTap: () => _openBrowser(context, imageSlots, page),
          ),
      };

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
  void _openBrowser(
    BuildContext context,
    List<_ImageSlot> imageSlots,
    int page,
  ) {
    showZoomableMediaDialog(
      context,
      viewer: PagedZoomableImages(
        itemCount: imageSlots.length,
        initialIndex: page,
        autofocus: true,
        pageBuilder: (context, i, rotation) => ZoomableImage.controlledRotation(
          bytes: imageSlots[i].image.bytes,
          maxDecodeExtent: _zoomDecodeExtent,
          // The thread's number, not the page. This is where someone decides
          // what to ask about, so the name they read here has to be the one
          // the model answers to.
          semanticLabel: 'Image ${imageSlots[i].number}',
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

/// The number naming a tile, in its corner.
///
/// Over the image rather than captioned under it. A caption costs every row of
/// attachments its own height, permanently, to keep a corner of a thumbnail
/// clear — and the thumbnail is a tap target for the full-size browser rather
/// than something to study, so that corner is cheap. It also puts a second row
/// of digits directly above the pills carrying the same numbers, which reads as
/// the layout having failed to join them up.
///
/// Painted in the pill's own colours, so the badge and the pill that says the
/// same number read as one thing in two places. Opaque rather than a scrim over
/// the image: at this size legibility cannot depend on what the photo happens
/// to hold underneath.
class _TileNumber extends StatelessWidget {
  const _TileNumber({required this.number, required this.isError});

  final int number;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tone = attachmentToneColors(theme.colorScheme, isError: isError);
    return ExcludeSemantics(
      // The tile underneath already announces this image by the same number, so
      // contributing the bare digit here would only have it read twice. An
      // empty `semanticsLabel` would leave a node behind rather than none.
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
        decoration: BoxDecoration(
          color: tone.background,
          borderRadius: BorderRadius.circular(context.radii.sm),
        ),
        child: Text(
          '$number',
          style: theme.textTheme.labelSmall?.copyWith(color: tone.foreground),
        ),
      ),
    );
  }
}

/// Stands in for an attachment that cannot be shown, filling the same 48 px
/// slot as a thumbnail so the tile row does not go ragged around it.
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
/// pointer, on long-press on a touch screen. A tile is 48 px square, with no
/// room to render it.
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

/// One attached image, as a tile in the row above the message text. Tapping
/// opens the full-size browser; a decode failure shows a broken-image fallback
/// in the same slot.
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
          // so a tall image is capped too — see `_tileDecodeExtent`.
          image: ResizeImage(
            MemoryImage(image.bytes),
            width: _tileDecodeExtent,
            height: _tileDecodeExtent,
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
