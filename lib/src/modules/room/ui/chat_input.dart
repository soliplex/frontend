import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_logging/soliplex_logging.dart';

import '../../../shared/document_display.dart';
import '../attachable_images.dart';
import '../pick_file.dart' show PickFileException;
import '../pick_image.dart';
import 'document_label.dart';
import 'inline_image_composer_controller.dart';
import 'package:soliplex_design/soliplex_design.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.chat_input');

/// Shown while the composer holds an image it cannot send, which is only ever
/// a draft that came back from re-authentication without its images. Removing
/// each one is the way past, so the message that goes out is the one on
/// screen.
const unrestoredImageNotice =
    'Remove the images that could not be restored to send this message.';

/// Whether the composer takes text right now. It refuses while the screen has
/// it disabled and while a run is in flight, because both render it read-only —
/// text routed in during either state could not be edited or removed until the
/// composer came back.
///
/// [ChatInput] gates its text field, send button, add-image button, document
/// filter, upload control, and document chip removal on this. Two things sit
/// outside it. The Stop button, by necessity: it renders only while a run holds
/// the composer, which is one of the states this refuses. And an inline image's
/// placeholder chip, whose tap target is a gesture inside the field that
/// `readOnly` does not reach — so a restored draft's unavailable images can
/// still be cleared while a run is in flight, which costs nothing, since they
/// block the send until they are gone either way.
bool composerAcceptsText({
  required bool enabled,
  required AgentSessionState? sessionState,
}) =>
    enabled && !_isRunActive(sessionState);

bool _isRunActive(AgentSessionState? state) =>
    state == AgentSessionState.spawning || state == AgentSessionState.running;

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onCancel,
    this.sessionState,
    this.cancelEnabled,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.selectedDocuments = const {},
    this.onFilterTap,
    this.onDocumentRemoved,
    this.onAttachFile,
    this.onAttachFolder,
    this.openImagePicker,
    this.composerScope,
  });

  final void Function(List<MessagePart> parts) onSend;
  final void Function() onCancel;
  final ReadonlySignal<AgentSessionState?>? sessionState;

  /// When provided, the Stop button is disabled while this signal is
  /// `false` (it still renders, since [sessionState] is `spawning` or
  /// `running`). Defaults to `true`.
  final ReadonlySignal<bool>? cancelEnabled;
  final InlineImageComposerController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final Set<RagDocument> selectedDocuments;
  final VoidCallback? onFilterTap;
  final void Function(RagDocument doc)? onDocumentRemoved;
  final VoidCallback? onAttachFile;

  /// Optional folder-pick callback. When both [onAttachFile] and
  /// [onAttachFolder] are non-null, the attach control becomes a popup
  /// menu with "Files…" and "Folder…" choices. When only [onAttachFile]
  /// is provided, the attach control stays a single-action icon. Below
  /// [SoliplexBreakpoints.tablet] with a document filter also present, the two
  /// are not a control of their own at all: they fold into the shared actions
  /// menu as "Upload files…" and "Upload folder…".
  final VoidCallback? onAttachFolder;

  /// Opens the image picker behind the add-image button. Defaults to the
  /// platform picker; a test supplies its own so the add-image path can be
  /// exercised without a plugin behind it.
  final Future<PickImagesResult?> Function()? openImagePicker;

  /// What the composer is composing for. Changing it drops the notice about
  /// the last pick, which describes a pick made into the conversation being
  /// left and would otherwise sit above the one being entered.
  ///
  /// Deliberately a plain field and not a [Key] on this widget. Keying it
  /// would re-inflate the composer, and re-inflating it closes the platform
  /// text input connection: the [FocusNode] belongs to the caller and outlives
  /// the rebuild, so nothing reports a focus change and `EditableText` never
  /// reopens the connection. The caret stays on screen while the soft keyboard
  /// drops and typing goes nowhere until the field is tapped again.
  final Object? composerScope;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

enum _AttachChoice { files, folder }

/// The optional room actions, which collapse into one menu on a narrow
/// composer.
enum _RoomActionChoice { filter, uploadFiles, uploadFolder }

class _ChatInputState extends State<ChatInput> {
  late InlineImageComposerController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _chipsExpanded = true;

  /// Why the last attempt to add images did not do all the user asked, held
  /// until a send, a change of conversation, or a pick that comes back with
  /// something to say replaces it. A cancel is none of those and leaves it
  /// standing, since the user may still need to read it.
  String? _attachNotice;

  /// Whether a pick is open, which closes the add-image button behind it.
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    _initController();
    _initFocusNode();
  }

  @override
  void didUpdateWidget(ChatInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      if (_ownsController) _controller.dispose();
      _initController();
    }
    if (widget.composerScope != oldWidget.composerScope) {
      _attachNotice = null;
    }
    if (widget.focusNode != oldWidget.focusNode) {
      if (_ownsFocusNode) _focusNode.dispose();
      _initFocusNode();
    }
  }

  void _initController() {
    if (widget.controller != null) {
      _controller = widget.controller!;
      _ownsController = false;
    } else {
      _controller = InlineImageComposerController();
      _ownsController = true;
    }
  }

  void _initFocusNode() {
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
      _ownsFocusNode = false;
    } else {
      _focusNode = FocusNode();
      _ownsFocusNode = true;
    }
  }

  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    if (_ownsFocusNode) _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    if (!composerAcceptsText(
      enabled: widget.enabled,
      sessionState: widget.sessionState?.peek(),
    )) {
      return;
    }
    final parts = _controller.sendableParts();
    if (parts == null) return;
    widget.onSend(parts);
    _controller.clear();
    setState(() => _attachNotice = null);
    _focusNode.requestFocus();
  }

  /// Runs one pick, and owns everything that can go wrong with it.
  ///
  /// Holds the button closed for the duration: a second pick over an open one
  /// is refused outright by the Android plugin, which would report a failure
  /// over a pick that is still working.
  ///
  /// The catch-all is not defensive padding. Nothing in the app installs a
  /// global async error handler, and this runs from a [VoidCallback], so any
  /// throw it does not model — from a picker the caller supplied, or from a
  /// platform this does not know about — would be dropped by the root zone.
  /// The user would be left tapping a button that does nothing, with no log
  /// line for anyone to work back from.
  Future<void> _addImages() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      await _attachPickedImages();
    } on PickFileException catch (error, stackTrace) {
      _logger.error(
        'image picker failed',
        error: error.cause,
        stackTrace: stackTrace,
      );
      if (mounted) {
        // Not the upload path's "could not open file picker": on web the bytes
        // are read inside the picker call, so a failure here is as likely to
        // have come after the chooser closed — which the user just watched
        // work.
        setState(
          () => _attachNotice = error.cause is RangeError
              ? 'The images are too large to load in the browser.'
              : 'Could not add the images.',
        );
      }
    } on Object catch (error, stackTrace) {
      _logger.error(
        'could not add images',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        setState(() => _attachNotice = 'Could not add the images.');
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// Picks images and inserts the ones this message may carry at the caret,
  /// reporting whatever it could not take.
  ///
  /// The composer's own images are what the limits are measured against, and
  /// they are read after the picker closes rather than before it opens: on web
  /// the page stays interactive while the chooser is up, so the composer can
  /// change under it.
  Future<void> _attachPickedImages() async {
    // A pick belongs to the conversation it was made into. The composer
    // deliberately survives a thread change — see [ChatInput.composerScope] —
    // so nothing else here would notice: it comes back mounted, enabled, and
    // holding someone else's draft.
    final scope = widget.composerScope;
    final result = await (widget.openImagePicker ?? pickImages)();
    if (result == null) return;

    // Logged before anything below can return early. A pick that comes back to
    // a composer that has gone away, that has moved to another conversation, or
    // that a run has taken, still has to leave a record of the files it could
    // not read — it is the only account of them, and those paths have nowhere
    // to show one.
    for (final error in result.errors) {
      _logger.error(
        'could not read a picked image',
        error: error.cause,
        attributes: {'filename': error.filename},
      );
    }

    // A batch with nothing in it is not a cancel, which comes back as null.
    // Android answers a pick it could not copy a single item out of this way,
    // having dropped the names on its side — so there is nothing to name, and
    // this line is the only record the pick happened at all.
    final pickedNothing = result.images.isEmpty && result.errors.isEmpty;
    if (pickedNothing) {
      _logger.error(
        'the image picker returned an empty batch',
        // The platform is the whole of what a reader has to go on here: the
        // batch names nothing, and which platform produced it is what says
        // whether this is the known Android case or something new.
        attributes: {'platform': defaultTargetPlatform.name},
      );
    }

    // Dropped without a word on a scope change: `didUpdateWidget` has already
    // cleared the notice slot, and a message about a pick made in the last
    // conversation is exactly what must not appear over this one.
    if (!mounted || widget.composerScope != scope) return;

    // The same window that lets the composer change can hand it to a run, which
    // renders it read-only. An image put there could not be removed until the
    // run ended — a chip showing its picture has no other way out — and would
    // then be sent with whatever the user typed next.
    if (!composerAcceptsText(
      enabled: widget.enabled,
      sessionState: widget.sessionState?.peek(),
    )) {
      setState(
        () => _attachNotice = 'The composer was busy. Add the images again.',
      );
      return;
    }

    if (pickedNothing) {
      setState(
        () => _attachNotice = 'Could not read the images you picked.',
      );
      return;
    }

    final selection = attachableImages(
      result.images,
      attached: _controller.contents
          .whereType<ComposerImageSlot>()
          .map((slot) => slot.image)
          .whereType<InlineImage>()
          .map((image) => image.part),
    );

    _controller.insertImagesAtCaret(selection.accepted);
    setState(
      () => _attachNotice = rejectedImagesNotice([
        for (final error in result.errors)
          (name: error.filename, reason: ImageRejection.unreadable),
        ...selection.rejected,
      ]),
    );
    _focusNode.requestFocus();
  }

  Widget _notice(
    BuildContext context, {
    required IconData icon,
    required String message,
    required Color color,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
      // A notice appears without taking focus, and is the only account of what
      // happened — the house style has no transient banner that would announce
      // itself.
      child: Semantics(
        liveRegion: true,
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: SoliplexSpacing.s1),
            Flexible(
              child: Text(
                message,
                style: theme.textTheme.bodySmall?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The composer's leading controls, at most two of them below
  /// [SoliplexBreakpoints.tablet].
  ///
  /// Add-image is always a button of its own. It is the only way to attach an
  /// image, and the only one of the three controls every room offers, so behind
  /// a menu it would cost a tap and buy nothing. The *optional* pair collapses
  /// instead, and only where the composer is too narrow to carry three: three
  /// 48 px buttons, the gap and the send button leave a 320 px composer a
  /// 104 px text field.
  ///
  /// Collapsing the pair holds the row at two slots whenever either optional
  /// action is already present, so the field does not resize under the user when
  /// the room's document load lands and reveals the filter mid-typing. A room
  /// with no upload affordance still shifts once, the first time the filter
  /// appears. Only below [SoliplexBreakpoints.tablet]: above it the row carries
  /// all three, so the filter arriving still widens it by a slot.
  List<Widget> _leadingControls(
    BuildContext context,
    BoxConstraints constraints, {
    required bool disabled,
  }) {
    final hasFilter = widget.onFilterTap != null;
    final hasUpload = widget.onAttachFile != null;
    final collapse = constraints.maxWidth < SoliplexBreakpoints.tablet &&
        hasFilter &&
        hasUpload;

    return [
      IconButton(
        icon: const Icon(Icons.add_photo_alternate_outlined),
        // Carries the semantics label, so a screen reader names the button.
        tooltip: 'Add image',
        // Never gated on the room's sandbox capability: that governs uploads to
        // the thread, while an inline image is a property of the model.
        onPressed: disabled || _picking ? null : _addImages,
      ),
      if (collapse)
        // Flattened rather than nested: upload is a menu of its own, and
        // Material handles a menu inside a menu poorly. Labelled items are a
        // gain of their own on touch, where a bare icon's tooltip never shows.
        PopupMenuButton<_RoomActionChoice>(
          // Not a second plus beside the add-image button: these are the rest
          // of the room's actions, which is what an overflow glyph says.
          icon: const Icon(Icons.more_horiz),
          tooltip: 'More actions',
          enabled: !disabled,
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: _RoomActionChoice.filter,
              child: Text('Filter documents'),
            ),
            const PopupMenuItem(
              value: _RoomActionChoice.uploadFiles,
              child: Text('Upload files…'),
            ),
            if (widget.onAttachFolder != null)
              const PopupMenuItem(
                value: _RoomActionChoice.uploadFolder,
                child: Text('Upload folder…'),
              ),
          ],
          onSelected: (choice) => switch (choice) {
            _RoomActionChoice.filter => widget.onFilterTap!(),
            _RoomActionChoice.uploadFiles => widget.onAttachFile!(),
            _RoomActionChoice.uploadFolder => widget.onAttachFolder!(),
          },
        )
      else ...[
        if (hasFilter)
          IconButton(
            icon: Icon(
              Icons.filter_alt,
              color: widget.selectedDocuments.isNotEmpty && !disabled
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
            tooltip: 'Filter documents',
            onPressed: disabled ? null : widget.onFilterTap,
          ),
        if (hasUpload)
          if (widget.onAttachFolder != null)
            PopupMenuButton<_AttachChoice>(
              icon: const Icon(Icons.attach_file),
              tooltip: 'Upload to thread',
              enabled: !disabled,
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _AttachChoice.files,
                  child: Text('Files…'),
                ),
                PopupMenuItem(
                  value: _AttachChoice.folder,
                  child: Text('Folder…'),
                ),
              ],
              onSelected: (choice) => switch (choice) {
                _AttachChoice.files => widget.onAttachFile!(),
                _AttachChoice.folder => widget.onAttachFolder!(),
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.attach_file),
              tooltip: 'Upload file to thread',
              onPressed: disabled ? null : widget.onAttachFile,
            ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.sessionState?.watch(context);
    final active = _isRunActive(state);
    final disabled =
        !composerAcceptsText(enabled: widget.enabled, sessionState: state);
    final cancelEnabled = widget.cancelEnabled?.watch(context) ?? true;

    // Measures the composer, not the row inside its padding, so the threshold
    // the leading controls collapse at does not move with that padding.
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.selectedDocuments.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
                padding: const EdgeInsets.all(SoliplexSpacing.s2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(context.radii.md),
                ),
                width: double.infinity,
                child: _chipsExpanded
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => setState(() => _chipsExpanded = false),
                            child: Row(
                              children: [
                                const Spacer(),
                                Text(
                                  'Hide',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                      ),
                                ),
                                Icon(
                                  Icons.expand_more,
                                  size: 16,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ],
                            ),
                          ),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 160),
                            child: SingleChildScrollView(
                              child: Wrap(
                                spacing: SoliplexSpacing.s1,
                                runSpacing: SoliplexSpacing.s1,
                                children: [
                                  for (final display in widget.selectedDocuments
                                      .map(DocumentDisplay.new))
                                    // A chip has room for a name and nothing
                                    // else, so two files embedded in different
                                    // documents under the same name read alike
                                    // here, having been told apart everywhere the
                                    // user chose them.
                                    Tooltip(
                                      message: documentProvenanceSentence(
                                        display.name,
                                        display.ancestorNames,
                                      ),
                                      waitDuration:
                                          const Duration(milliseconds: 500),
                                      child: SoliplexChip(
                                        icon: Icon(
                                          display.icon,
                                        ),
                                        label: Text(display.name),
                                        onDeleted: widget.onDocumentRemoved ==
                                                    null ||
                                                disabled
                                            ? null
                                            : () => widget.onDocumentRemoved!(
                                                  display.document,
                                                ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => setState(() => _chipsExpanded = true),
                        child: Row(
                          children: [
                            Text(
                              '${widget.selectedDocuments.length} documents selected',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                            ),
                            const Spacer(),
                            Icon(
                              Icons.expand_less,
                              size: 16,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ],
                        ),
                      ),
              ),
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) =>
                  _controller.hasPlaceholderImage
                      ? _notice(
                          context,
                          icon: Icons.image_not_supported_outlined,
                          message: unrestoredImageNotice,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        )
                      : const SizedBox.shrink(),
            ),
            if (_attachNotice case final notice?)
              _notice(
                context,
                icon: Icons.error_outline,
                message: notice,
                color: Theme.of(context).colorScheme.error,
              ),
            Row(
              children: [
                ..._leadingControls(context, constraints, disabled: disabled),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): _send,
                    },
                    child: SoliplexInput(
                      controller: _controller,
                      focusNode: _focusNode,
                      readOnly: disabled,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      hintText: 'Type a message...',
                    ),
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                if (active)
                  IconButton(
                    icon: const Icon(Icons.stop),
                    onPressed: cancelEnabled ? widget.onCancel : null,
                  )
                else
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _controller,
                    builder: (context, value, child) => IconButton(
                      icon: const Icon(Icons.send),
                      onPressed:
                          disabled || !_controller.canSend ? null : _send,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
