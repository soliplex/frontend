import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import 'members_widgets.dart';
import 'role_visuals.dart';
import 'room_access.dart';

/// The dialog's largest size, where the screen leaves room for it.
const double _dialogMaxWidth = 560;
const double _dialogMaxHeight = 680;

/// What the dialog asks the card to add: people, or one login rule.
typedef AddAccessRequest = ({List<AccessSubject> subjects, RoomRole role});

/// A dialog when there is room and the whole screen when not.
///
/// [loadChecks] is asked only when the user turns to login rules, and may
/// answer with a read already made. [reloadChecks] asks the server again,
/// for Try again.
Future<AddAccessRequest?> showAddAccessDialog(
  BuildContext context, {
  required RoomPolicy policy,
  required Future<List<LoginCheck>> Function() loadChecks,
  required Future<List<LoginCheck>> Function() reloadChecks,
}) {
  final narrow = MediaQuery.sizeOf(context).width < SoliplexBreakpoints.tablet;
  return showDialog<AddAccessRequest>(
    context: context,
    builder: (context) {
      final child = AddAccessDialog(
        policy: policy,
        loadChecks: loadChecks,
        reloadChecks: reloadChecks,
      );
      if (narrow) return Dialog.fullscreen(child: child);
      return Dialog(
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: _dialogMaxWidth,
            maxHeight: _dialogMaxHeight,
          ),
          child: child,
        ),
      );
    },
  );
}

enum _Mode { people, rule }

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
class AddAccessDialog extends StatefulWidget {
  const AddAccessDialog({
    required this.policy,
    required this.loadChecks,
    required this.reloadChecks,
    super.key,
  });

  final RoomPolicy policy;
  final Future<List<LoginCheck>> Function() loadChecks;
  final Future<List<LoginCheck>> Function() reloadChecks;

  @override
  State<AddAccessDialog> createState() => _AddAccessDialogState();
}

class _AddAccessDialogState extends State<AddAccessDialog> {
  _Mode _mode = _Mode.people;
  RoomRole _role = RoomRole.member;
  List<_ParsedEmail> _emails = const [];
  Future<List<LoginCheck>>? _checks;
  String? _check;

  void _setMode(_Mode mode) => setState(() {
        _mode = mode;
        if (mode == _Mode.rule) _checks ??= _handled(widget.loadChecks());
      });

  void _retryChecks() => setState(() {
        _checks = _handled(widget.reloadChecks());
      });

  // Marked handled at once: a quick failure can land before the pane's
  // FutureBuilder subscribes, and the pane shows it either way.
  static Future<List<LoginCheck>> _handled(Future<List<LoginCheck>> checks) =>
      checks..ignore();

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
    final check = _check;
    final rule = _mode == _Mode.rule && check != null ? ruleFor(check) : null;
    final AddAccessRequest? request = switch (_mode) {
      _Mode.people when addable.isNotEmpty => (
          subjects: [for (final e in addable) AccessSubject.email(e.address)],
          role: _role,
        ),
      _Mode.rule when rule != null => (subjects: [rule], role: _role),
      _ => null,
    };
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add access', style: theme.textTheme.titleLarge),
              const SizedBox(height: SoliplexSpacing.s3),
              SegmentedButton<_Mode>(
                segments: const [
                  ButtonSegment(
                    value: _Mode.people,
                    label: Text('People'),
                    icon: Icon(Icons.person_outline),
                  ),
                  ButtonSegment(
                    value: _Mode.rule,
                    label: Text('Login rule'),
                    icon: Icon(Icons.rule),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (s) => _setMode(s.first),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_mode == _Mode.rule)
                  _RulePane(
                    checks: _checks!,
                    policy: widget.policy,
                    selected: _check,
                    onSelected: (name) => setState(() => _check = name),
                    onRetry: _retryChecks,
                  )
                else ...[
                  SoliplexInput(
                    label: 'Email addresses',
                    hintText:
                        'One or several, separated by commas or new lines',
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
                ],
                const SizedBox(height: SoliplexSpacing.s3),
              ],
            ),
          ),
        ),
        // Outside the scroll, so the choice stays in view however long the
        // list of addresses or checks runs.
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
                  switch (_mode) {
                    _Mode.people when skipped > 0 =>
                      '${addable.length} to add, $skipped skipped.',
                    _Mode.rule when check == null => 'Pick a check.',
                    _ => '',
                  },
                  style: mutedStyle(context, theme.textTheme.bodySmall),
                ),
              ),
              SoliplexButton.text(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: SoliplexSpacing.s2),
              SoliplexButton.filled(
                onPressed: request == null
                    ? null
                    : () => Navigator.pop<AddAccessRequest>(context, request),
                icon: Icon(
                  _mode == _Mode.rule
                      ? Icons.rule
                      : Icons.person_add_alt_outlined,
                  size: 18,
                ),
                child: Text(
                  _mode == _Mode.rule
                      ? 'Add rule'
                      : addable.length <= 1
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

/// The server's checks to build a rule from, each with what it says it does.
class _RulePane extends StatefulWidget {
  const _RulePane({
    required this.checks,
    required this.policy,
    required this.selected,
    required this.onSelected,
    required this.onRetry,
  });

  final Future<List<LoginCheck>> checks;
  final RoomPolicy policy;
  final String? selected;
  final ValueChanged<String> onSelected;
  final VoidCallback onRetry;

  @override
  State<_RulePane> createState() => _RulePaneState();
}

class _RulePaneState extends State<_RulePane> {
  /// Past this, the list earns a search.
  static const _searchFrom = 7;

  String _search = '';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = mutedStyle(context, theme.textTheme.bodySmall);
    return FutureBuilder<List<LoginCheck>>(
      future: widget.checks,
      builder: (context, snapshot) {
        // First, because a snapshot keeps the last future's error and data
        // while a new one runs: a retry would otherwise show the old failure.
        if (snapshot.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.all(SoliplexSpacing.s6),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        if (snapshot.hasError) {
          return snapshot.error is NotFoundException
              ? const AccessNotice(
                  text: "This server can't list its checks, so login rules "
                      'can only be added with soliplex-cli until it is '
                      'updated.',
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const AccessNotice(
                      tone: NoticeTone.error,
                      text: "Couldn't load the server's checks.",
                    ),
                    const SizedBox(height: SoliplexSpacing.s2),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SoliplexButton.text(
                        onPressed: widget.onRetry,
                        icon: const Icon(Icons.refresh, size: 18),
                        child: const Text('Try again'),
                      ),
                    ),
                  ],
                );
        }
        final all = snapshot.requireData;
        // A name that wouldn't read back as a rule couldn't be shown or
        // changed here once added.
        final checks = [
          for (final c in all)
            if (ruleFor(c.name) != null) c,
        ];
        if (checks.isEmpty) {
          return const AccessNotice(
            text: 'The server has no checks registered, so there is nothing '
                'to build a rule from. Checks are registered in the '
                "server's configuration.",
          );
        }
        final query = _search.trim().toLowerCase();
        final matching = [
          for (final c in checks)
            if (query.isEmpty ||
                c.name.toLowerCase().contains(query) ||
                (c.description?.toLowerCase().contains(query) ?? false))
              c,
        ];
        final rows = widget.policy.rows;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'A rule gives the role to everyone whose login passes a check '
              'the server has registered. Who passes is decided at sign-in, '
              'so it cannot be previewed here.',
              style: muted,
            ),
            if (checks.length >= _searchFrom) ...[
              const SizedBox(height: SoliplexSpacing.s3),
              SoliplexInput(
                hintText: 'Search checks',
                leadingIcon: const Icon(Icons.search),
                onChanged: (v) => setState(() => _search = v),
              ),
            ],
            const SizedBox(height: SoliplexSpacing.s2),
            if (matching.isEmpty)
              Padding(
                padding: const EdgeInsets.all(SoliplexSpacing.s4),
                child: Text(
                  'No check matches this search.',
                  textAlign: TextAlign.center,
                  style: muted,
                ),
              ),
            for (final c in matching)
              Builder(
                builder: (context) {
                  final subject = ruleFor(c.name);
                  final listed =
                      rows.where((r) => r.subject == subject).firstOrNull;
                  final isSelected = widget.selected == c.name;
                  final description = c.description ?? 'No description given';
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: listed == null,
                    selected: isSelected,
                    leading: const Icon(Icons.rule),
                    trailing: isSelected ? const Icon(Icons.check) : null,
                    title: Text(
                      c.name,
                      style: context.monospaceOn(theme.textTheme.bodyMedium),
                    ),
                    subtitle: Text(
                      listed == null
                          ? description
                          : '$description · already '
                              '${listed.role?.label ?? 'listed'}',
                    ),
                    onTap: () => widget.onSelected(c.name),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}
