import 'package:flutter/material.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../composer_draft.dart';
import 'markdown/log_source.dart';

final _logger = LogManager.instance
    .getLogger('soliplex_frontend.inline_image_composer_controller');

/// Where image tokens are allocated from: the Private Use Area, which carries
/// no meaning of its own.
///
/// A single UTF-16 code unit is what makes an image atomic to edit: backspace
/// removes the whole thing and the caret cannot land inside it, with no key
/// handling of our own. Giving each image its own unit is what makes it
/// identifiable: the character names the image, so no edit to the text can
/// desynchronise it from the images the composer holds.
const int _firstImageToken = 0xE000;

/// The draft marker, as the code unit a restore walk reads.
final int _draftMarkerToken = composerDraftImageMarker.codeUnitAt(0);

/// Edge length of an image's chip in the composer.
const double _thumbnailSize = SoliplexSpacing.s6;

/// Long-edge bound on a chip thumbnail's *decode*. `Image`'s width and height
/// bound layout only — the engine decodes the full bitmap otherwise, ~48 MB of
/// RGBA for a 12 MP photo, for each image in the composer. Nothing downscales
/// what the user picked, so the composer holds originals.
const int _thumbnailDecodeExtent = 256;

/// What an image token in the composer's text names.
sealed class ComposerImage {
  /// Creates a composer image.
  const ComposerImage();
}

/// An image the composer holds the bytes of, ready to send.
final class InlineImage extends ComposerImage {
  /// Creates an inline image carrying [part].
  const InlineImage(this.part);

  /// The image, as a send would carry it.
  final ImagePart part;
}

/// An image a restored draft knows the position of but not the content of.
///
/// A draft persists positions and no bytes, so this is the expected outcome of
/// coming back from re-authentication — not a fault. It reads as informational
/// rather than as an error, and blocks the send until the user removes it.
final class UnavailableImage extends ComposerImage {
  /// Creates a placeholder for an image a draft could not bring back.
  const UnavailableImage();
}

/// One element of the composer's ordered content, read from its text.
sealed class ComposerContent {
  /// Creates a content element.
  const ComposerContent();
}

/// A run of text between images.
final class ComposerTextRun extends ComposerContent {
  /// Creates a text run carrying [text].
  const ComposerTextRun(this.text);

  /// The text. Never empty.
  final String text;
}

/// The place one image occupies in the text.
final class ComposerImageSlot extends ComposerContent {
  /// Creates a slot for the image [token] names.
  const ComposerImageSlot({required this.token, required this.image});

  /// The code unit naming this image in the composer's text.
  final int token;

  /// The image, or null when the token's image has been released while the
  /// character survived — an edit undone after a send, or a defect of ours.
  /// Either way the composer is showing an image it cannot produce, so it
  /// renders as an error and blocks the send.
  final ComposerImage? image;
}

/// A composer whose text carries images inline, so what the user writes around
/// them survives editing and reaches the model in the order they wrote it.
///
/// Each image is one code unit in [text] paired with a chip rendered from
/// [buildTextSpan]; the images themselves are held beside the text, keyed by
/// that code unit. Order and membership are read from the text on every pass,
/// so an edit can neither reorder the images nor leave one naming the wrong
/// bytes. Only a code unit this controller minted counts — a character the
/// user typed is text, whatever block it comes from.
///
/// Images are released when the content is replaced wholesale — [clear] on
/// send or on a room or thread change, and [restoreDraft] — rather than the
/// moment their code unit leaves the text. Identity follows the character, so
/// a token that comes back must still name its own image: cutting one and
/// pasting it elsewhere reorders that image, and an undone deletion brings it
/// back intact. Releasing on the edit would strand both.
///
/// While the text holds no image, rendering is delegated whole to
/// [TextEditingController], IME composition underline included. Once it holds
/// one, the composing region is no longer underlined: a composing range is
/// expressed in offsets over the whole text, and splitting the runs to style
/// it is not worth its cost against the images it would sit between.
///
/// One constraint the chips depend on: `EditableText` renders spell-check
/// results itself and never calls this class when it has any, so enabling
/// spell check on the composer's field would replace every chip with a raw
/// placeholder character.
class InlineImageComposerController extends TextEditingController {
  final Map<int, ComposerImage> _images = <int, ComposerImage>{};

  /// Every code unit this controller has minted, outliving the images
  /// themselves so that a token whose image was released still reads as one.
  ///
  /// Membership here, rather than a code-unit range, is what makes a character
  /// a token: the Private Use Area is full of characters users legitimately
  /// type and paste — the Apple logo, a terminal's Nerd Font glyphs — and
  /// reading those as images would put a chip over the user's own text.
  final Set<int> _mintedTokens = <int>{};

  int _nextToken = _firstImageToken;

  bool _isImageToken(int unit) => _mintedTokens.contains(unit);

  /// Allocates a code unit for one image, skipping any the text it is about to
  /// join already carries — minting one of those would put a second chip over
  /// a character the user typed.
  ///
  /// Never reuses a unit: a reused one would let an undo resurrect a token
  /// that now names a different image, the ambiguity the per-image unit exists
  /// to remove.
  int _mintToken(Set<int> inUse) {
    while (inUse.contains(_nextToken)) {
      _nextToken++;
    }
    final token = _nextToken++;
    _mintedTokens.add(token);
    return token;
  }

  /// Empties the composer, releasing every image it holds.
  @override
  void clear() {
    _images.clear();
    super.clear();
  }

  /// Inserts [images] at the caret in order, replacing the selection.
  ///
  /// Takes images that are already allowed: what may be attached, how many,
  /// and how large is the picker's business, not a text controller's.
  void insertImagesAtCaret(List<ImagePart> images) {
    if (images.isEmpty) return;
    final inUse = text.codeUnits.toSet();
    final tokens = StringBuffer();
    for (final image in images) {
      final token = _mintToken(inUse);
      _images[token] = InlineImage(image);
      tokens.writeCharCode(token);
    }
    _replaceSelection(tokens.toString());
  }

  /// Replaces the composer's content with a draft persisted across an
  /// auth-expiry redirect.
  ///
  /// A draft carries every image's position and none of its bytes, so each
  /// marker becomes a token of its own with an [UnavailableImage] behind it —
  /// leaving a restored composer structurally identical to a live one.
  void restoreDraft(String draft) {
    _images.clear();
    // A token equal to a character the draft already carries would put a
    // second chip over that character.
    final inUse = draft.codeUnits.toSet();
    final restored = StringBuffer();
    for (final unit in draft.codeUnits) {
      if (unit == _draftMarkerToken) {
        final token = _mintToken(inUse);
        _images[token] = const UnavailableImage();
        restored.writeCharCode(token);
      } else {
        restored.writeCharCode(unit);
      }
    }
    final text = restored.toString();
    value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  /// The composer's ordered content, as the text spells it out.
  List<ComposerContent> get contents => _contentsOf(text);

  /// The ordered parts a send would carry, or null when the composer has
  /// nothing to send.
  ///
  /// Refuses two payloads rather than sending them:
  /// - one carrying neither an image nor any text, which reaches the backend
  ///   as empty content and is discarded there without an error;
  /// - one where an image is only a placeholder, since dropping it would send
  ///   a different message from the one the composer is showing.
  List<MessagePart>? sendableParts() {
    final parts = <MessagePart>[];
    for (final content in _contentsOf(text.trim())) {
      switch (content) {
        case ComposerTextRun(:final text):
          parts.add(TextPart(text));
        case ComposerImageSlot(image: InlineImage(:final part)):
          parts.add(part);
        case ComposerImageSlot():
          return null;
      }
    }
    if (parts.plainText.isEmpty && !parts.hasAttachment) return null;
    return parts;
  }

  /// Whether the composer holds something it can send.
  bool get canSend => sendableParts() != null;

  /// Whether any image is a placeholder — restored from a draft, or a token
  /// whose image has been released.
  bool get hasPlaceholderImage => contents.any(
        (content) =>
            content is ComposerImageSlot && content.image is! InlineImage,
      );

  /// How many images the composer holds bytes for. Between edits this exceeds
  /// the number of image tokens in [text] by design — a deleted image is kept
  /// so undoing the deletion brings it back — but it must reach zero once the
  /// content is replaced.
  @visibleForTesting
  int get heldImageCount => _images.values.whereType<InlineImage>().length;

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (!text.codeUnits.any(_isImageToken)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(
      style: style,
      children: [
        for (final content in contents)
          switch (content) {
            ComposerTextRun(:final text) => TextSpan(text: text),
            ComposerImageSlot(:final token, :final image) => WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: _ImageChip(
                  token: token,
                  image: image,
                  onRemove: () => _removeImage(token),
                ),
              ),
          },
      ],
    );
  }

  List<ComposerContent> _contentsOf(String source) {
    final contents = <ComposerContent>[];
    final run = StringBuffer();

    void flushText() {
      if (run.isEmpty) return;
      contents.add(ComposerTextRun(run.toString()));
      run.clear();
    }

    for (final unit in source.codeUnits) {
      if (_isImageToken(unit)) {
        flushText();
        contents.add(ComposerImageSlot(token: unit, image: _images[unit]));
      } else {
        run.writeCharCode(unit);
      }
    }
    flushText();
    return contents;
  }

  void _replaceSelection(String insertion) {
    // A selection the text cannot accommodate — never placed, or left behind
    // by an edit while the picker was open — appends rather than throwing out
    // of `replaceRange`. Matches `insertPastedText`, which takes the same care
    // with the same value.
    final fits = selection.isValid && selection.end <= text.length;
    final start = fits ? selection.start : text.length;
    final end = fits ? selection.end : text.length;
    value = TextEditingValue(
      text: text.replaceRange(start, end, insertion),
      selection: TextSelection.collapsed(offset: start + insertion.length),
    );
  }

  /// Takes [token] out of the text, wherever the user carried it to.
  void _removeImage(int token) {
    final at = text.codeUnits.indexOf(token);
    if (at < 0) return;
    value = TextEditingValue(
      text: String.fromCharCodes(
        text.codeUnits.where((unit) => unit != token),
      ),
      selection: TextSelection.collapsed(offset: at),
    );
  }
}

/// One image, inline in the composer's text.
///
/// Renders three states, which mean three different things: the image itself;
/// a placeholder for one a draft could not bring back, which is expected and
/// reads as such; and an error-coloured `missing` for a token whose image has
/// been released. Both placeholders are tappable, because they block the send
/// and removing them is the only way past. A fourth is possible inside the
/// first: bytes that will not decode paint a broken glyph in the thumbnail's
/// place, which does not block the send — this app failing to decode an image
/// does not mean the model will.
class _ImageChip extends StatelessWidget {
  const _ImageChip({
    required this.token,
    required this.image,
    required this.onRemove,
  });

  /// Identifies the image in the decode-failure log, so a chip that will not
  /// render can be told from its neighbour.
  final int token;
  final ComposerImage? image;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
      child: switch (image) {
        InlineImage(:final part) => _thumbnail(context, part),
        UnavailableImage() => _placeholder(
            context,
            icon: Icons.image_not_supported_outlined,
            label: 'unavailable',
            description: 'This image was not kept across sign-in. '
                'Tap to remove it.',
            background: colors.secondaryContainer,
            foreground: colors.onSecondaryContainer,
          ),
        null => _placeholder(
            context,
            icon: Icons.broken_image_outlined,
            label: 'missing',
            description: 'This image is no longer available. Tap to remove it.',
            background: colors.errorContainer,
            foreground: colors.onErrorContainer,
          ),
      },
    );
  }

  Widget _thumbnail(BuildContext context, ImagePart part) {
    final radius = BorderRadius.circular(context.radii.sm);
    return ClipRRect(
      borderRadius: radius,
      child: Image(
        // `.fit` scales the long edge into the box and keeps the aspect ratio,
        // where `.exact` would decode to a squashed 256×256.
        image: ResizeImage(
          MemoryImage(part.bytes),
          width: _thumbnailDecodeExtent,
          height: _thumbnailDecodeExtent,
          policy: ResizeImagePolicy.fit,
        ),
        width: _thumbnailSize,
        height: _thumbnailSize,
        fit: BoxFit.cover,
        semanticLabel: 'Attached image',
        errorBuilder: (context, error, stack) {
          logFailedSourceOnce(
            _logger,
            'composer image decode failed '
                '(${part.mimeType}, ${part.bytes.length} bytes)',
            'composer:$token',
            error: error,
            stackTrace: stack,
          );
          return Icon(
            Icons.broken_image_outlined,
            size: _thumbnailSize,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          );
        },
      ),
    );
  }

  Widget _placeholder(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String description,
    required Color background,
    required Color foreground,
  }) =>
      Semantics(
        button: true,
        label: description,
        child: Tooltip(
          message: description,
          // Announced by the Semantics above; a tooltip that contributed it
          // too would have a screen reader read the chip twice.
          excludeFromSemantics: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onRemove,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s1),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(context.radii.sm),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 16, color: foreground),
                  const SizedBox(width: SoliplexSpacing.s1),
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: foreground),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
