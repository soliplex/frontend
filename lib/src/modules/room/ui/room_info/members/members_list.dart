import 'package:flutter/material.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import 'members_widgets.dart';
import 'role_visuals.dart';
import 'room_access.dart';

enum _Filter {
  all('All'),
  admin('Admin'),
  member('Member'),
  reader('Reader'),
  rules('Login rules');

  const _Filter(this.label);

  final String label;

  IconData? get icon => switch (this) {
        _Filter.all => null,
        _Filter.admin => RoomRole.admin.icon,
        _Filter.member => RoomRole.member.icon,
        _Filter.reader => RoomRole.reader.icon,
        _Filter.rules => Icons.rule,
      };

  bool matches(MemberRow row) => switch (this) {
        _Filter.all => true,
        _Filter.admin => row.role == RoomRole.admin,
        _Filter.member => row.role == RoomRole.member,
        _Filter.reader => row.role == RoomRole.reader,
        _Filter.rules => row.group == RowGroup.rules,
      };
}

class MembersList extends StatefulWidget {
  const MembersList(
      {required this.policy,
      required this.viewerClaims,
      required this.onAdd,
      required this.onChangeRole,
      required this.onRemove,
      super.key});

  final RoomPolicy policy;
  final Map<String, dynamic>? viewerClaims;
  final VoidCallback onAdd;
  final void Function(MemberRow row, RoomRole role) onChangeRole;
  final ValueChanged<MemberRow> onRemove;

  @override
  State<MembersList> createState() => _MembersListState();
}

class _MembersListState extends State<MembersList> {
  /// Past this, a list earns the search and chips the threads list has.
  static const _searchFrom = 9;

  /// The rows a long list shows until asked for the rest.
  static const _pageSize = 25;

  final _searchController = TextEditingController();
  String _search = '';
  _Filter _filter = _Filter.all;
  bool _showAll = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final policy = widget.policy;
    final rows = policy.rows;
    final searchable = rows.length >= _searchFrom;
    final visible = rows
        .where(_filter.matches)
        .where(
          (r) =>
              _search.isEmpty ||
              displayName(r.subject).toLowerCase().contains(_search),
        )
        .toList();
    final truncated = !_showAll && visible.length > _pageSize;
    final shown = truncated ? visible.take(_pageSize).toList() : visible;
    final hasDeny = rows.any((r) => r.hasDeny);
    final muted = mutedStyle(context, theme.textTheme.bodySmall);

    Widget section(RowGroup group, String title, String? help) {
      final inGroup = shown.where((r) => r.group == group).toList();
      if (inGroup.isEmpty) return const SizedBox.shrink();
      final total = visible.where((r) => r.group == group).length;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: SoliplexSpacing.s4,
              bottom: SoliplexSpacing.s1,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: title),
                      TextSpan(text: '  $total', style: muted),
                    ],
                  ),
                  style: theme.textTheme.titleSmall,
                ),
                if (help != null) Text(help, style: muted),
              ],
            ),
          ),
          for (final row in inGroup)
            _MemberTile(
              key: ValueKey(row.subject),
              row: row,
              isYou: row.isViewer(widget.viewerClaims),
              onChangeRole: (role) => widget.onChangeRole(row, role),
              onRemove: () => widget.onRemove(row),
            ),
        ],
      );
    }

    // Reachable only by removing the last entry from here, by someone who
    // reached the room through it: with nobody listed, nobody can open it.
    if (rows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Posture(policy: policy),
          const SizedBox(height: SoliplexSpacing.s3),
          Text(
            'Nobody is listed, so nobody can open this room.',
            textAlign: TextAlign.center,
            style: mutedStyle(context, theme.textTheme.bodyMedium),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Align(child: _AddButton(onPressed: widget.onAdd)),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            // Beside the room's state when there is room for both, as the
            // primary action of everything below it.
            if (constraints.maxWidth < 480) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Posture(policy: policy),
                  const SizedBox(height: SoliplexSpacing.s3),
                  _AddButton(onPressed: widget.onAdd),
                ],
              );
            }
            return Row(
              children: [
                Expanded(child: _Posture(policy: policy)),
                const SizedBox(width: SoliplexSpacing.s3),
                _AddButton(onPressed: widget.onAdd),
              ],
            );
          },
        ),
        if (policy.defaultEffect == AccessEffect.allow) ...[
          const SizedBox(height: SoliplexSpacing.s3),
          const AccessNotice(
            icon: Icons.lock_open_outlined,
            text: 'Anyone signed in can read this room. The entries below only '
                'add more than that, so removing someone does not stop them '
                'reading.',
          ),
        ],
        if (hasDeny) ...[
          const SizedBox(height: SoliplexSpacing.s3),
          const AccessNotice(
            text: 'This room has deny entries. The server stops at the first '
                'entry that matches, so a deny can outrank a person listed '
                'here. This list does not show that order.',
          ),
        ],
        if (searchable) ...[
          const SizedBox(height: SoliplexSpacing.s3),
          SoliplexInput(
            controller: _searchController,
            hintText: 'Search people and rules',
            leadingIcon: const Icon(Icons.search),
            onChanged: (v) => setState(() {
              _search = v.trim().toLowerCase();
            }),
          ),
          const SizedBox(height: SoliplexSpacing.s2),
          Wrap(
            spacing: SoliplexSpacing.s2,
            runSpacing: SoliplexSpacing.s1,
            children: [
              for (final filter in _Filter.values)
                SoliplexChip.filter(
                  label: Text(
                    '${filter.label} ${rows.where(filter.matches).length}',
                  ),
                  icon: filter.icon == null ? null : Icon(filter.icon),
                  selected: _filter == filter,
                  onSelected: (_) => setState(() => _filter = filter),
                ),
            ],
          ),
        ],
        section(RowGroup.people, 'People', null),
        section(
          RowGroup.rules,
          'Login rules',
          'Everyone whose login passes the check',
        ),
        section(
          RowGroup.other,
          'Set outside this card',
          'Shown as stored and kept when others change',
        ),
        if (truncated)
          Padding(
            padding: const EdgeInsets.only(top: SoliplexSpacing.s2),
            child: SoliplexButton.outlined(
              onPressed: () => setState(() => _showAll = true),
              icon: const Icon(Icons.unfold_more, size: 18),
              child: Text('Show all ${visible.length}'),
            ),
          ),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: SoliplexSpacing.s4),
            child: Column(
              children: [
                Text(
                  'Nobody matches this search.',
                  style: mutedStyle(context, theme.textTheme.bodyMedium),
                ),
                SoliplexButton.text(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _search = '';
                      _filter = _Filter.all;
                    });
                  },
                  child: const Text('Clear search and filters'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The card's primary action, the same control wherever it appears.
class _AddButton extends StatelessWidget {
  const _AddButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => SoliplexButton.filled(
        onPressed: onPressed,
        icon: const Icon(Icons.person_add_alt_outlined, size: 18),
        child: const Text('Add people'),
      );
}

/// The room's default, always in view. It cannot be changed here, which is
/// what makes changing it hard.
class _Posture extends StatelessWidget {
  const _Posture({required this.policy});

  final RoomPolicy policy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final open = policy.defaultEffect == AccessEffect.allow;
    return Wrap(
      spacing: SoliplexSpacing.s2,
      runSpacing: SoliplexSpacing.s1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StateBadge(
          label: open ? 'Open to read' : 'Private',
          icon: open ? Icons.lock_open_outlined : Icons.lock_outline,
          intent: open ? BadgeIntent.warning : BadgeIntent.success,
        ),
        if (!open)
          Text(
            'Only the people and rules below can open this room.',
            style: mutedStyle(context, theme.textTheme.bodySmall),
          ),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.row,
    required this.isYou,
    required this.onChangeRole,
    required this.onRemove,
    super.key,
  });

  final MemberRow row;
  final bool isYou;
  final ValueChanged<RoomRole> onChangeRole;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subject = row.subject;
    final isRule = row.isRule;
    final mono = isRule ||
        subject.kind == AccessSubjectKind.jsonPath ||
        subject.kind == AccessSubjectKind.preferredUsername;
    final subtitle = switch (subject.kind) {
      AccessSubjectKind.preferredUsername => 'Login username',
      AccessSubjectKind.jsonPath =>
        isRule ? 'Checked at sign-in' : 'Custom rule on login claims',
      AccessSubjectKind.authenticated => 'Any signed-in user',
      AccessSubjectKind.everyone => 'Anyone at all',
      AccessSubjectKind.email => null,
    };
    const youBadge = SoliplexBadge(
      label: Text('You'),
      icon: Icon(Icons.person_outline),
    );
    Widget name({required bool withYou}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                displayName(subject),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono
                    ? context.monospaceOn(theme.textTheme.bodyMedium)
                    : theme.textTheme.bodyMedium,
              ),
            ),
            if (isYou && withYou) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              youBadge,
            ],
          ],
        );
    Widget detail({required bool withYou}) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            name(withYou: withYou),
            if (subtitle != null)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mutedStyle(context, theme.textTheme.bodySmall),
              ),
          ],
        );
    Widget actions({required bool aligned}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // A long entry such as "Denied read, Allowed write" shrinks rather
            // than overflows a narrow row: neither pill can wrap.
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: _access(context),
              ),
            ),
            if (isYou && !aligned) ...[
              const SizedBox(width: SoliplexSpacing.s2),
              youBadge,
            ],
            if (row.editable && !isYou)
              IconButton(
                icon: Icon(row.removeIcon),
                tooltip: row.removeLabel,
                onPressed: onRemove,
                // Quiet at rest, because there is one on every row; the
                // destructive colour arrives as the pointer does.
                style: ButtonStyle(
                  foregroundColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused)
                        ? theme.colorScheme.error
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (aligned)
              // Keeps the role chips in one column down the list.
              const SizedBox(width: 48, height: 48),
          ],
        );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Too narrow to hold an address beside its controls, and an address
        // is the thing that must stay readable.
        final narrow = constraints.maxWidth < 420;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: SoliplexSpacing.s1),
          child: Row(
            children: [
              _Avatar(subject: subject, denied: row.hasDeny),
              const SizedBox(width: SoliplexSpacing.s3),
              if (narrow)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      detail(withYou: false),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: actions(aligned: false),
                      ),
                    ],
                  ),
                )
              else ...[
                Expanded(child: detail(withYou: true)),
                const SizedBox(width: SoliplexSpacing.s2),
                actions(aligned: true),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _access(BuildContext context) {
    final role = row.role;
    if (isYou && role != null) {
      return Tooltip(
        message: 'Ask another administrator to change your own access',
        child: SoliplexChip(
          label: Text(role.label),
          icon: const Icon(Icons.lock_outline),
          intent: role.chipIntent,
        ),
      );
    }
    if (row.editable) {
      return _RoleMenu(current: role!, onSelected: onChangeRole);
    }
    const message = 'Shown as stored, and kept when others are edited. '
        'Change it on the server, with room-authz.';
    if (role != null) {
      return Tooltip(message: message, child: RoleBadge(role));
    }
    // Not a role: a deny is the one that takes access away, and anything else
    // is unusual enough to be worth a second look.
    return Tooltip(
      message: message,
      child: SoliplexBadge(
        label: Text(row.rawSummary),
        icon: Icon(row.hasDeny ? Icons.block : Icons.help_outline),
        intent: row.hasDeny ? BadgeIntent.danger : BadgeIntent.warning,
      ),
    );
  }
}

/// The role chip, which opens the roles. Admin is listed only for a row that
/// already holds it, so it can be taken away but not given.
class _RoleMenu extends StatefulWidget {
  const _RoleMenu({required this.current, required this.onSelected});

  final RoomRole current;
  final ValueChanged<RoomRole> onSelected;

  @override
  State<_RoleMenu> createState() => _RoleMenuState();
}

class _RoleMenuState extends State<_RoleMenu> {
  // The same idiom as the server sidebar's menu: the chip takes the tap, and
  // opens the menu through this key.
  final _menu = GlobalKey<PopupMenuButtonState<RoomRole>>();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.current;
    final roles = [
      ...RoomRole.offered,
      if (!RoomRole.offered.contains(current)) current,
    ];
    return PopupMenuButton<RoomRole>(
      key: _menu,
      tooltip: 'Change role',
      onSelected: widget.onSelected,
      itemBuilder: (context) => [
        for (final role in roles)
          PopupMenuItem(
            value: role,
            padding: const EdgeInsets.symmetric(
              horizontal: SoliplexSpacing.s3,
              vertical: SoliplexSpacing.s2,
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 24,
                  child: role == current
                      ? const Icon(Icons.check, size: 18)
                      : null,
                ),
                const SizedBox(width: SoliplexSpacing.s2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RoleBadge(role),
                      const SizedBox(height: SoliplexSpacing.s1),
                      Text(
                        role.description,
                        style: mutedStyle(context, theme.textTheme.bodySmall),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
      child: SoliplexChip.action(
        onPressed: () => _menu.currentState?.showButtonMenu(),
        intent: current.chipIntent,
        icon: Icon(current.icon),
        label: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(current.label),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.subject, this.denied = false});

  final AccessSubject subject;
  final bool denied;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPerson = subject.kind == AccessSubjectKind.email;
    final value = subject.value ?? '';
    final initial = isPerson && !denied && value.isNotEmpty;
    return CircleAvatar(
      radius: 16,
      backgroundColor: denied
          ? theme.colorScheme.errorContainer
          : theme.colorScheme.surfaceContainerHighest,
      foregroundColor: denied
          ? theme.colorScheme.onErrorContainer
          : theme.colorScheme.onSurface,
      child: initial
          ? Text(
              value.characters.first.toUpperCase(),
              style: theme.textTheme.labelMedium,
            )
          : Icon(
              switch (subject.kind) {
                _ when denied => Icons.block,
                AccessSubjectKind.jsonPath when ruleName(subject) != null =>
                  Icons.rule,
                AccessSubjectKind.preferredUsername => Icons.badge_outlined,
                AccessSubjectKind.jsonPath => Icons.data_object,
                _ => Icons.groups_outlined,
              },
              size: 18,
            ),
    );
  }
}
