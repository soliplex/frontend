import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../../../../soliplex_frontend.dart';
import '../../../shared/file_type_icons.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onCancel,
    this.sessionState,
    this.controller,
    this.focusNode,
    this.enabled = true,
    this.selectedDocuments = const {},
    this.onFilterTap,
    this.onDocumentRemoved,
    this.onAttachFile,
  });

  final void Function(String text) onSend;
  final void Function() onCancel;
  final ReadonlySignal<AgentSessionState?>? sessionState;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final Set<RagDocument> selectedDocuments;
  final VoidCallback? onFilterTap;
  final void Function(RagDocument doc)? onDocumentRemoved;
  final VoidCallback? onAttachFile;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;
  bool _chipsExpanded = true;

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
      _controller = TextEditingController();
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
    final text = _controller.text.trim();
    if (text.isEmpty ||
        !widget.enabled ||
        _isActive(widget.sessionState?.peek())) {
      return;
    }
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  bool _isActive(AgentSessionState? state) =>
      state == AgentSessionState.spawning || state == AgentSessionState.running;

  @override
  Widget build(BuildContext context) {
    final state = widget.sessionState?.watch(context);
    final active = _isActive(state);
    final disabled = !widget.enabled || active;

    return Padding(
      padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s9, SoliplexSpacing.s2,
          SoliplexSpacing.s2, SoliplexSpacing.s4),
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
                borderRadius: BorderRadius.circular(8),
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
                                      color:
                                          Theme.of(context).colorScheme.primary,
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
                              spacing: 4,
                              runSpacing: 4,
                              children: [
                                for (final doc in widget.selectedDocuments)
                                  Chip(
                                    avatar: Icon(
                                      getFileTypeIcon(
                                        documentIconPath(doc),
                                      ),
                                      size: 16,
                                    ),
                                    label: Text(documentDisplayName(doc)),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 16,
                                    ),
                                    onDeleted:
                                        widget.onDocumentRemoved == null ||
                                                disabled
                                            ? null
                                            : () => widget.onDocumentRemoved!(
                                                  doc,
                                                ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
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
                                  color: Theme.of(context).colorScheme.primary,
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
          Row(
            children: [
              if (widget.onFilterTap != null)
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
              if (widget.onAttachFile != null)
                IconButton(
                  icon: const Icon(Icons.attach_file),
                  tooltip: 'Upload file to thread',
                  onPressed: disabled ? null : widget.onAttachFile,
                ),
              Expanded(
                child: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): _send,
                  },
                  child: TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    readOnly: disabled,
                    maxLines: null,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ),
              if (active)
                IconButton(
                  icon: const Icon(Icons.stop),
                  onPressed: widget.onCancel,
                )
              else
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _controller,
                  builder: (context, value, _) => IconButton(
                    icon: const Icon(Icons.send),
                    onPressed:
                        value.text.trim().isEmpty || disabled ? null : _send,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
