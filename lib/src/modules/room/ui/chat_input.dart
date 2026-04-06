import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import '../../../../soliplex_frontend.dart';

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onCancel,
    this.sessionState,
    this.controller,
    this.focusNode,
    this.enabled = true,
  });

  final void Function(String text) onSend;
  final void Function() onCancel;
  final ReadonlySignal<AgentSessionState?>? sessionState;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  late TextEditingController _controller;
  late FocusNode _focusNode;
  bool _ownsController = false;
  bool _ownsFocusNode = false;

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
    if (text.isEmpty || !widget.enabled) return;
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
      padding: const EdgeInsets.fromLTRB(SoliplexSpacing.s6, SoliplexSpacing.s2, SoliplexSpacing.s2, SoliplexSpacing.s4),
      child: Row(
        children: [
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
                onPressed: value.text.trim().isEmpty || disabled ? null : _send,
              ),
            ),
        ],
      ),
    );
  }
}
