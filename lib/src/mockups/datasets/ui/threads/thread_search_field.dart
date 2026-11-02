import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:soliplex_client/soliplex_client.dart' show ThreadLabel;
import 'package:soliplex_design/soliplex_design.dart';

import '../../../../modules/lobby/ui/thread_search_field.dart'
    show kThreadSearchDebounce;
import '../../../../shared/label_chip.dart';
import 'thread_query.dart';

// MOCKUP: a copy of the lobby's `ThreadSearchField` that completes rooms
// after `in:` as well as labels after `@`, and offers `@no-label` and
// `in:none` for threads with neither.

/// One entry in the completion menu.
class _Suggestion {
  const _Suggestion.label(ThreadLabel this.label)
      : name = null,
        kind = TokenKind.label,
        none = false;
  const _Suggestion.noLabel()
      : label = null,
        name = 'No label',
        kind = TokenKind.label,
        none = true;
  const _Suggestion.room(String this.name, {this.none = false})
      : label = null,
        kind = TokenKind.room;

  final ThreadLabel? label;
  final String? name;
  final TokenKind kind;

  /// Whether this stands for no label, or no room, rather than one.
  final bool none;

  /// What the token is completed to.
  String get token =>
      label?.name.toLowerCase() ??
      switch ((kind, none)) {
        (TokenKind.label, true) => noLabelToken,
        (TokenKind.room, true) => noRoomToken,
        _ => name!.toLowerCase(),
      };
}

class ThreadSearchField extends StatefulWidget {
  const ThreadSearchField({
    super.key,
    required this.labels,
    required this.roomNames,
    required this.onChanged,
  });

  final List<ThreadLabel> labels;

  /// The rooms `in:` completes, by display name.
  final List<String> roomNames;

  final ValueChanged<ThreadQuery> onChanged;

  @override
  State<ThreadSearchField> createState() => ThreadSearchFieldState();
}

class ThreadSearchFieldState extends State<ThreadSearchField> {
  static const String _tapGroup = 'mockup-thread-search-suggestions';

  final TextEditingController _controller = TextEditingController();
  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final OverlayPortalController _overlay = OverlayPortalController();
  final LayerLink _link = LayerLink();

  Timer? _debounce;
  List<_Suggestion> _suggestions = const [];
  int _highlighted = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
  }

  static final Set<LogicalKeyboardKey> _ownedKeys = {
    LogicalKeyboardKey.arrowDown,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.tab,
    LogicalKeyboardKey.enter,
    LogicalKeyboardKey.numpadEnter,
    LogicalKeyboardKey.escape,
  };

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_overlay.isShowing || _suggestions.isEmpty) {
      return KeyEventResult.ignored;
    }
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
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

  void _moveHighlight(int delta) {
    setState(() {
      final count = _suggestions.length;
      _highlighted = (_highlighted + delta + count) % count;
    });
  }

  @override
  void didUpdateWidget(ThreadSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
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
    _debounce?.cancel();
    _debounce = Timer(kThreadSearchDebounce, () {
      if (mounted) widget.onChanged(parseThreadQuery(_controller.text));
    });
  }

  void _refreshSuggestions() {
    final selection = _controller.selection;
    final cursor =
        selection.isValid && selection.isCollapsed ? selection.baseOffset : -1;
    final active = activeToken(_controller.text, cursor);
    if (active == null) {
      _hide();
      return;
    }

    final already =
        parseThreadQuery(_controller.text).namesOf(active.kind).toSet();
    final candidates = switch (active.kind) {
      TokenKind.label => [
          const _Suggestion.noLabel(),
          for (final label in widget.labels) _Suggestion.label(label),
        ],
      TokenKind.room => [
          const _Suggestion.room('No room', none: true),
          for (final name in widget.roomNames) _Suggestion.room(name),
        ],
    };
    final matches = [
      for (final s in candidates)
        if ((s.token.contains(active.partial) ||
                (s.name?.toLowerCase().contains(active.partial) ?? false)) &&
            !already.contains(s.token))
          s,
    ];

    setState(() {
      _suggestions = matches;
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

  void _complete(_Suggestion suggestion) {
    final selection = _controller.selection;
    final cursor = selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : _controller.text.length;
    final completed = completeToken(_controller.text, cursor, suggestion.token);
    if (completed == null) return;

    _controller.value = TextEditingValue(
      text: completed.text,
      selection: TextSelection.collapsed(offset: completed.cursor),
    );
    _hide();
    _debounce?.cancel();
    widget.onChanged(parseThreadQuery(_controller.text));
  }

  void _onSubmitted(String _) {
    if (_overlay.isShowing && _suggestions.isNotEmpty) {
      _complete(_suggestions.first);
      return;
    }
    _debounce?.cancel();
    widget.onChanged(parseThreadQuery(_controller.text));
  }

  /// Adds [name] as a [kind] token unless the query already has it, and
  /// applies the query at once: a tap on a row's label filters by it.
  void addToken(TokenKind kind, String name) {
    final token = name.toLowerCase();
    final text = _controller.text;
    if (parseThreadQuery(text).namesOf(kind).contains(token)) return;
    final lead = text.isEmpty || text.endsWith(' ') ? text : '$text ';
    final next = '$lead${formatToken(kind, token)} ';
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    _debounce?.cancel();
    widget.onChanged(parseThreadQuery(next));
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
            hintText: 'Name, @label or in:room',
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
        child: TapRegion(
          groupId: _tapGroup,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(context.radii.md),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 320),
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) => _SuggestionRow(
                  suggestion: _suggestions[index],
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

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.suggestion,
    required this.highlighted,
    required this.onTap,
    required this.onHover,
  });

  final _Suggestion suggestion;
  final bool highlighted;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final label = suggestion.label;
    return MouseRegion(
      onEnter: (_) => onHover(),
      child: InkWell(
        onTap: onTap,
        canRequestFocus: false,
        child: Container(
          color: highlighted ? theme.colorScheme.primaryContainer : null,
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s3,
            vertical: SoliplexSpacing.s2,
          ),
          child: Row(
            children: [
              if (label != null) ...[
                LabelChip(label: label),
                const Spacer(),
                if (label.usageCount != null)
                  Text(
                    '${label.usageCount}',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ] else ...[
                if (suggestion.kind == TokenKind.label)
                  Icon(Icons.label_off_outlined, size: 18, color: muted)
                else
                  RoomLinkIcon(roomless: suggestion.none),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: Text(
                    suggestion.name!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether a thread lives in a room: a door for one that does, a lone
/// bubble for a conversation outside every room.
class RoomLinkIcon extends StatelessWidget {
  const RoomLinkIcon({required this.roomless, this.tooltip, super.key});

  final bool roomless;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      roomless ? Icons.chat_bubble_outline : Icons.meeting_room_outlined,
      size: 18,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return tooltip == null ? icon : Tooltip(message: tooltip, child: icon);
  }
}
