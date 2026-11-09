import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import 'members_widgets.dart';
import 'role_visuals.dart';
import 'room_access.dart';

/// What the dialog asks the card to add.
typedef AddPeopleRequest = ({List<AccessSubject> people, RoomRole role});

/// A dialog when there is room and the whole screen when not.
///
/// People only: adding a login rule needs the list of checks the server has
/// registered, which no endpoint returns yet.
Future<AddPeopleRequest?> showAddPeopleDialog(
  BuildContext context, {
  required RoomPolicy policy,
}) {
  final narrow = MediaQuery.sizeOf(context).width < SoliplexBreakpoints.tablet;
  return showDialog<AddPeopleRequest>(
    context: context,
    builder: (context) {
      final child = AddPeopleDialog(policy: policy);
      if (narrow) return Dialog.fullscreen(child: child);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560, maxHeight: 680),
          child: child,
        ),
      );
    },
  );
}

enum _EmailState { ready, readyCheckCase, already, malformed }

class _ParsedEmail {
  const _ParsedEmail(this.address, this.state, [this.detail]);

  final String address;
  final _EmailState state;
  final String? detail;

  bool get addable =>
      state == _EmailState.ready || state == _EmailState.readyCheckCase;
}

@visibleForTesting
class AddPeopleDialog extends StatefulWidget {
  const AddPeopleDialog({required this.policy, super.key});

  final RoomPolicy policy;

  @override
  State<AddPeopleDialog> createState() => _AddPeopleDialogState();
}

class _AddPeopleDialogState extends State<AddPeopleDialog> {
  RoomRole _role = RoomRole.member;
  List<_ParsedEmail> _emails = const [];

  // A typo guard, not validation: the server stores any string.
  static final _emailShape = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  void _parse(String text) {
    final rows = widget.policy.rows;
    final seen = <String>{};
    final parsed = <_ParsedEmail>[];
    for (final address in text.split(RegExp(r'[,;\s]+'))) {
      if (address.isEmpty || !seen.add(address)) continue;
      final subject = AccessSubject.email(address);
      final existing = rows.where((r) => r.subject == subject);
      if (!_emailShape.hasMatch(address)) {
        parsed.add(
          _ParsedEmail(address, _EmailState.malformed, 'not an address'),
        );
      } else if (existing.isNotEmpty) {
        final role = existing.first.role;
        parsed.add(
          _ParsedEmail(
            address,
            _EmailState.already,
            role == null ? 'already listed' : 'already ${role.label}',
          ),
        );
      } else if (address != address.toLowerCase()) {
        parsed.add(
          _ParsedEmail(
            address,
            _EmailState.readyCheckCase,
            'capitals must match their sign-in exactly',
          ),
        );
      } else {
        parsed.add(_ParsedEmail(address, _EmailState.ready));
      }
    }
    setState(() => _emails = parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final addable = _emails.where((e) => e.addable).toList();
    final skipped = _emails.length - addable.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s6,
            SoliplexSpacing.s6,
            SoliplexSpacing.s6,
            SoliplexSpacing.s3,
          ),
          child: Text('Add people', style: theme.textTheme.titleLarge),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoliplexInput(
                  label: 'Email addresses',
                  hintText: 'One or several, separated by commas or new lines',
                  helperText: 'Accounts are not checked. Access starts when '
                      'the person signs in with exactly this address.',
                  minLines: 2,
                  maxLines: 4,
                  autofocus: true,
                  onChanged: _parse,
                ),
                if (_emails.isNotEmpty) ...[
                  const SizedBox(height: SoliplexSpacing.s3),
                  for (final email in _emails) _EmailLine(email),
                ],
                const SizedBox(height: SoliplexSpacing.s3),
              ],
            ),
          ),
        ),
        // Outside the scroll, so the choice stays in view however long the
        // list of addresses runs.
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SoliplexSpacing.s6,
            SoliplexSpacing.s3,
            SoliplexSpacing.s6,
            SoliplexSpacing.s3,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => SoliplexDropdown<RoomRole>(
              label: 'Role',
              width: constraints.maxWidth,
              initialValue: _role,
              helperText: _role.description,
              entries: [
                for (final role in RoomRole.offered)
                  SoliplexDropdownEntry(
                    value: role,
                    label: role.label,
                    icon: Icon(role.icon, size: 18),
                  ),
              ],
              onSelected: (role) {
                if (role != null) setState(() => _role = role);
              },
            ),
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.all(SoliplexSpacing.s4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  skipped > 0
                      ? '${addable.length} to add, $skipped skipped.'
                      : '',
                  style: mutedStyle(context, theme.textTheme.bodySmall),
                ),
              ),
              SoliplexButton.text(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.filled(
                onPressed: addable.isEmpty
                    ? null
                    : () => Navigator.pop<AddPeopleRequest>(context, (
                          people: [
                            for (final e in addable)
                              AccessSubject.email(e.address),
                          ],
                          role: _role,
                        )),
                icon: const Icon(Icons.person_add_alt_outlined, size: 18),
                child: Text(
                  addable.length <= 1
                      ? 'Add person'
                      : 'Add ${addable.length} people',
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _EmailLine extends StatelessWidget {
  const _EmailLine(this.email);

  final _ParsedEmail email;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s1),
      child: Row(
        children: [
          Icon(
            switch (email.state) {
              _EmailState.ready => Icons.check_circle_outline,
              _EmailState.readyCheckCase => Icons.warning_amber,
              _EmailState.already => Icons.remove_circle_outline,
              _EmailState.malformed => Icons.block,
            },
            size: 18,
            color: switch (email.state) {
              _EmailState.ready => context.success,
              _EmailState.readyCheckCase => context.warning,
              _EmailState.already => theme.colorScheme.onSurfaceVariant,
              _EmailState.malformed => theme.colorScheme.error,
            },
          ),
          const SizedBox(width: SoliplexSpacing.s2),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: email.address),
                  if (email.detail case final detail?)
                    TextSpan(
                      text: ' · $detail',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}
