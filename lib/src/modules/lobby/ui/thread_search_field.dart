import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

import '../thread_query.dart';
import 'labels_view.dart' show LabelChip;

/// How long typing settles before the listing is refetched.
///
/// Long enough that typing a word costs one request rather than one per
/// keystroke, short enough that the list feels tied to the box.
const Duration kThreadSearchDebounce = Duration(milliseconds: 300);

/// The threads tab's search box: free text and `@label` in one field.
///
/// `Osprey Manual @manuals` narrows by name and by label at once; either
/// half works alone. Typing `@` opens a menu of matching labels, which
/// only ever *selects* — a user cannot coin a label from here, because
/// only administrators may create one.
class ThreadSearchField extends StatefulWidget {
  const ThreadSearchField({
    super.key,
    required this.labels,
    required this.onChanged,
  });

  /// The server's catalogue, for the suggestions.
  final List<ThreadLabel> labels;

  /// Fires with the parsed query once typing settles.
  final ValueChanged<ThreadQuery> onChanged;

  @override
  State<ThreadSearchField> createState() => _ThreadSearchFieldState();
}

class _ThreadSearchFieldState extends State<ThreadSearchField> {
  /// Ties the field and its menu into one tap region.
  ///
  /// Dismissal keys off tapping outside that region rather than off the
  /// field losing focus. Focus is the tempting signal and the wrong one:
  /// tapping a suggestion moves focus off the field, which would hide
  /// the menu — and unmount the very item being tapped — before the tap
  /// completed. The result is a menu you can see and cannot click.
  static const String _tapGroup = 'thread-search-suggestions';

  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();

  Timer? _debounce;

  /// Labels matching the `@` token being typed, or empty when none is.
  List<ThreadLabel> _suggestions = const [];

  /// Which suggestion the keyboard would take.
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  /// Handles the keys the menu owns while it is open.
  ///
  /// Hooked to the field's own focus node so it sees them before the
  /// text editor does — otherwise the arrows would move the caret and
  /// Tab would move focus out of the field entirely.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_overlay.isShowing || _suggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      // Claim the release of any key we act on, so a Tab-up does not
      // reach the traversal machinery after we swallowed its Tab-down.
      return _ownedKeys.contains(event.logicalKey)
          ? KeyEventResult.handled
          : KeyEventResult.ignored;
    }

    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        _moveHighlight(1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveHighlight(-1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.tab:
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        _complete(_suggestions[_highlighted]);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.escape:
        _hide();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // Not const: 'LogicalKeyboardKey' overrides '==', which a const set
  // may not contain.
  static final Set<LogicalKeyboardKey> _ownedKeys = {
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.escape,
  };

  void _moveHighlight(int delta) {
    setState(() {
      // Wraps, so holding a direction cycles rather than sticking.
      final count = _suggestions.length;
      _highlighted = (_highlighted + delta + count) % count;
    });
  }

  @override
  void didUpdateWidget(ThreadSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The catalogue can arrive after the field is built, or change while
    // the menu is open; recompute against whatever is current.
    if (!identical(oldWidget.labels, widget.labels)) _refreshSuggestions();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged() {
    _refreshSuggestions();

    // Debounced so a word costs one request, not one per keystroke.
    _debounce?.cancel();
    _debounce = Timer(kThreadSearchDebounce, () {
      if (mounted) widget.onChanged(parseThreadQuery(_controller.text));
    });
  }

  void _refreshSuggestions() {
    final selection = _controller.selection;
    // A ranged or unset selection has no single cursor to read a token
    // at, so there is nothing to complete.
    final cursor =
        selection.isValid && selection.isCollapsed ? selection.baseOffset : -1;
    final token = activeLabelToken(_controller.text, cursor);

    if (token == null) {
      _hide();
      return;
    }

    final already = parseThreadQuery(_controller.text).labelNames.toSet();
    final matches = [
      for (final label in widget.labels)
        // Case-folded on both sides, because label names ignore case —
        // matching literally would make '@Urgent' suggest nothing.
        if (label.name.toLowerCase().contains(token) &&
            !already.contains(label.name.toLowerCase()))
          label,
    ];

    setState(() {
      _suggestions = matches;
      // Back to the top whenever the list changes underneath: keeping an
      // index into a different list would highlight an arbitrary entry.
      _highlighted = 0;
    });
    if (matches.isEmpty) {
      _hide();
    } else {
      _overlay.show();
    }
  }

  void _hide() {
    if (_overlay.isShowing) _overlay.hide();
  }

  void _complete(ThreadLabel label) {
    final selection = _controller.selection;
    final cursor = selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : _controller.text.length;

    final completed = completeLabelToken(
      _controller.text,
      cursor,
      label.name.toLowerCase(),
    );
    if (completed == null) return;

    _controller.value = TextEditingValue(
      text: completed.text,
      selection: TextSelection.collapsed(offset: completed.cursor),
    );
    _hide();
    // Deliberately immediate rather than debounced: picking from the
    // menu is a decision, not typing.
    _debounce?.cancel();
    widget.onChanged(parseThreadQuery(_controller.text));
  }

  void _onSubmitted(String _) {
    // Enter takes the first suggestion when the menu is open — otherwise
    // it would commit a half-typed '@man' as a label name that matches
    // nothing.
    if (_overlay.isShowing && _suggestions.isNotEmpty) {
      _complete(_suggestions.first);
      return;
    }
    _debounce?.cancel();
    widget.onChanged(parseThreadQuery(_controller.text));
  }

  void _clear() {
    _controller.clear();
    _hide();
    _debounce?.cancel();
    widget.onChanged(ThreadQuery.empty);
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal(
      controller: _overlay,
      overlayChildBuilder: _buildSuggestions,
      child: TapRegion(
        groupId: _tapGroup,
        onTapOutside: (_) => _hide(),
        child: CompositedTransformTarget(
          link: _link,
          child: SoliplexInput(
            controller: _controller,
            focusNode: _focus,
            label: 'Search threads',
            hintText: 'Name, or @label',
            leadingIcon: const Icon(Icons.search),
            trailingIcon: _controller.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Clear',
                    onPressed: _clear,
                  ),
            onSubmitted: _onSubmitted,
          ),
        ),
      ),
    );
  }

  Widget _buildSuggestions(BuildContext context) {
    return CompositedTransformFollower(
      link: _link,
      targetAnchor: Alignment.bottomLeft,
      followerAnchor: Alignment.topLeft,
      offset: const Offset(0, SoliplexSpacing.s1),
      child: Align(
        alignment: Alignment.topLeft,
        // Same group as the field, so tapping a suggestion counts as
        // "inside" and does not dismiss the menu out from under the tap.
        child: TapRegion(
          groupId: _tapGroup,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(context.radii.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxHeight: 240,
                maxWidth: 320,
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(
                  vertical: SoliplexSpacing.s1,
                ),
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) => _SuggestionRow(
                  label: _suggestions[index],
                  highlighted: index == _highlighted,
                  onTap: () => _complete(_suggestions[index]),
                  onHover: () {
                    if (_highlighted != index) {
                      setState(() => _highlighted = index);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One suggestion in the `@label` menu.
class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.label,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final ThreadLabel label;

  /// Whether Enter or Tab would take this one.
  final bool highlighted;

  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        // The field keeps focus while the menu is used: a suggestion
        // taking it would both hide the menu and drop the caret.
        canRequestFocus: false,
        child: Container(
          color: highlighted ? theme.colorScheme.primaryContainer : null,
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s3,
            vertical: SoliplexSpacing.s2,
          ),
          child: Row(
            children: [
              LabelChip(label: label),
              const Spacer(),
              if (label.usageCount != null)
                Text(
                  '${label.usageCount}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
