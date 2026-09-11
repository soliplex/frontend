import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

import '../../../modules/room/ui/room_rail.dart' show roomAvatarColor;
import 'panel_state.dart';

/// First cut of the workspace: a note from this thread to colleagues —
/// title, body, embedded documents, recipients. A very small internal mail
/// client, which is the shape the fuller integration will grow out of.
class WorkspaceTab extends StatefulWidget {
  const WorkspaceTab({required this.state, super.key});

  final ThreadPanelState state;

  @override
  State<WorkspaceTab> createState() => _WorkspaceTabState();
}

class _WorkspaceTabState extends State<WorkspaceTab> {
  TextEditingController get _title => widget.state.noteTitle;
  TextEditingController get _content => widget.state.noteContent;

  @override
  void initState() {
    super.initState();
    _title.addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _title.removeListener(_changed);
    super.dispose();
  }

  void _send() {
    final names = widget.state.recipients.map((c) => c.name).join(', ');
    widget.state.sendNote();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Sent to $names')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final canSend =
        state.recipients.isNotEmpty && _title.text.trim().isNotEmpty;

    return SingleChildScrollView(
      controller: state.scrollFor('workspace'),
      padding: const EdgeInsets.fromLTRB(
        SoliplexSpacing.s6,
        SoliplexSpacing.s3,
        SoliplexSpacing.s6,
        SoliplexSpacing.s6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('To',
                  style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
              const SizedBox(width: SoliplexSpacing.s3),
              _AvatarStack(contacts: state.recipients),
              if (state.recipients.isNotEmpty)
                const SizedBox(width: SoliplexSpacing.s1),
              _RecipientPicker(state: state),
              const Spacer(),
              if (state.recipients.isEmpty)
                Text(
                  'Pick recipients',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s6),
          SoliplexInput(label: 'Title', controller: _title),
          const SizedBox(height: SoliplexSpacing.s4),
          SoliplexInput(
            label: 'Content',
            controller: _content,
            minLines: 5,
            maxLines: 10,
            keyboardType: TextInputType.multiline,
          ),
          const SizedBox(height: SoliplexSpacing.s3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DocumentPicker(state: state),
              const SizedBox(width: SoliplexSpacing.s1),
              Expanded(
                child: state.embeddedDocuments.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.only(top: SoliplexSpacing.s3),
                        child: Text(
                          'Embed documents from this room',
                          style:
                              theme.textTheme.bodySmall?.copyWith(color: muted),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.only(top: SoliplexSpacing.s1),
                        child: Wrap(
                          spacing: SoliplexSpacing.s1,
                          runSpacing: SoliplexSpacing.s1,
                          children: [
                            for (final doc in state.embeddedDocuments)
                              SoliplexChip(
                                icon: const Icon(Icons.description_outlined),
                                label: Text(doc.title),
                                onDeleted: () => state.toggleEmbedded(doc.id),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: SoliplexSpacing.s6),
          Row(
            children: [
              Expanded(
                child: Text(
                  state.sentCount > 0
                      ? '${state.sentCount} sent from this thread'
                      : '',
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.filled(
                icon: const Icon(Icons.send),
                onPressed: canSend ? _send : null,
                child: const Text('Send'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recipients as overlapping initials, in reading order.
class _AvatarStack extends StatelessWidget {
  const _AvatarStack({required this.contacts});

  final List<WorkspaceContact> contacts;

  static const _diameter = 32.0;
  static const _overlap = 10.0;

  @override
  Widget build(BuildContext context) {
    if (contacts.isEmpty) return const SizedBox.shrink();
    final width = _diameter + (contacts.length - 1) * (_diameter - _overlap);
    return SizedBox(
      width: width,
      height: _diameter,
      child: Stack(
        children: [
          for (final (i, contact) in contacts.indexed)
            Positioned(
              left: i * (_diameter - _overlap),
              child: _Avatar(contact: contact),
            ),
        ],
      ),
    );
  }
}

/// Initials on the same hue-from-name colour the rail gives rooms, so people
/// and rooms share one avatar language. The ring in the panel colour
/// separates overlapping avatars.
class _Avatar extends StatelessWidget {
  const _Avatar({required this.contact});

  final WorkspaceContact contact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = roomAvatarColor(contact.name, theme.brightness);
    return Tooltip(
      message: contact.name,
      child: CircleAvatar(
        radius: _AvatarStack._diameter / 2,
        backgroundColor: theme.colorScheme.surface,
        child: CircleAvatar(
          radius: _AvatarStack._diameter / 2 - 2,
          backgroundColor: bg,
          child: Text(
            contact.initials,
            style: theme.textTheme.labelSmall?.copyWith(
              color: contrastingForeground(bg),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

/// The `+` after the avatars: a checklist of colleagues.
class _RecipientPicker extends StatelessWidget {
  const _RecipientPicker({required this.state});

  final ThreadPanelState state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MenuAnchor(
      menuChildren: [
        for (final contact in state.contacts)
          CheckboxMenuButton(
            value: state.isRecipient(contact.id),
            onChanged: (_) => state.toggleRecipient(contact.id),
            closeOnActivate: false,
            child: Text(contact.name),
          ),
      ],
      builder: (context, controller, _) => Tooltip(
        message: 'Add recipients',
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: controller.isOpen ? controller.close : controller.open,
          child: Container(
            width: _AvatarStack._diameter,
            height: _AvatarStack._diameter,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outline),
            ),
            child: Icon(Icons.add, size: 18, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

/// The link icon: a checklist of the room's documents to embed.
class _DocumentPicker extends StatelessWidget {
  const _DocumentPicker({required this.state});

  final ThreadPanelState state;

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: [
        for (final doc in state.documents)
          CheckboxMenuButton(
            value: state.isEmbedded(doc.id),
            onChanged: (_) => state.toggleEmbedded(doc.id),
            closeOnActivate: false,
            child: Text(doc.title),
          ),
      ],
      builder: (context, controller, _) => IconButton(
        icon: const Icon(Icons.link),
        tooltip: 'Embed a document',
        onPressed: controller.isOpen ? controller.close : controller.open,
      ),
    );
  }
}
