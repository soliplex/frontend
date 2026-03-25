import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

class ChatInput extends StatefulWidget {
  const ChatInput({
    super.key,
    required this.onSend,
    required this.onCancel,
    required this.sessionState,
  });

  final void Function(String text) onSend;
  final void Function() onCancel;
  final ReadonlySignal<AgentSessionState?> sessionState;

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    widget.onSend(text);
    _controller.clear();
    _focusNode.requestFocus();
  }

  bool _isActive(AgentSessionState? state) =>
      state == AgentSessionState.spawning || state == AgentSessionState.running;

  @override
  Widget build(BuildContext context) {
    final state = widget.sessionState.watch(context);
    final active = _isActive(state);

    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              enabled: !active,
              maxLines: null,
              textInputAction: TextInputAction.newline,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          if (active)
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: widget.onCancel,
            )
          else
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: _controller.text.trim().isEmpty ? null : _send,
            ),
        ],
      ),
    );
  }
}
