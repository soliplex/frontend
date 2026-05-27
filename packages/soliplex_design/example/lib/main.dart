import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() => runApp(const GalleryApp());

class GalleryApp extends StatelessWidget {
  const GalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'soliplex_design gallery',
      theme: soliplexLightTheme(),
      darkTheme: soliplexDarkTheme(),
      home: const GalleryHome(),
    );
  }
}

/// Tabbed shell hosting one gallery per component family.
class GalleryHome extends StatefulWidget {
  const GalleryHome({super.key});

  @override
  State<GalleryHome> createState() => _GalleryHomeState();
}

class _GalleryHomeState extends State<GalleryHome> {
  ThemeMode _themeMode = ThemeMode.light;

  static const _sections = <(String, Widget)>[
    ('Buttons', ButtonGallery()),
    ('Badges', BadgeGallery()),
    ('Chips', ChipGallery()),
    ('Inputs', InputGallery()),
    ('Dropdowns', DropdownGallery()),
    ('Pickers', PickerGallery()),
  ];

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _themeMode == ThemeMode.light
          ? soliplexLightTheme()
          : soliplexDarkTheme(),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return DefaultTabController(
            length: _sections.length,
            child: Scaffold(
              backgroundColor: theme.scaffoldBackgroundColor,
              appBar: AppBar(
                title: const Text('soliplex_design'),
                bottom: TabBar(
                  tabs: [
                    for (final (label, _) in _sections) Tab(text: label),
                  ],
                ),
                actions: [
                  IconButton(
                    icon: Icon(
                      _themeMode == ThemeMode.light
                          ? Icons.dark_mode
                          : Icons.light_mode,
                    ),
                    onPressed: () => setState(
                      () => _themeMode = _themeMode == ThemeMode.light
                          ? ThemeMode.dark
                          : ThemeMode.light,
                    ),
                  ),
                ],
              ),
              body: TabBarView(
                children: [
                  for (final (_, gallery) in _sections)
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(SoliplexSpacing.s4),
                      child: gallery,
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

// =====================================================================
// Buttons
// =====================================================================

/// Gallery of every `SoliplexButton` variant. Reused by golden tests so
/// the snapshot matches the runnable app.
class ButtonGallery extends StatelessWidget {
  const ButtonGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: 'Filled',
          children: _shapeRow(_ButtonShape.filled),
        ),
        _Section(
          title: 'Outlined',
          children: _shapeRow(_ButtonShape.outlined),
        ),
        _Section(
          title: 'Text',
          children: _shapeRow(_ButtonShape.text),
        ),
        _Section(
          title: 'Text — compact',
          children: _shapeRow(_ButtonShape.text, compact: true),
        ),
      ],
    );
  }

  List<Widget> _shapeRow(_ButtonShape shape, {bool compact = false}) {
    return [
      _GalleryButton(shape: shape, intent: ButtonIntent.primary, label: 'Save'),
      _GalleryButton(
        shape: shape,
        intent: ButtonIntent.primary,
        label: 'Save',
        icon: const Icon(Icons.check),
      ),
      _GalleryButton(
        shape: shape,
        intent: ButtonIntent.primary,
        label: 'Saving…',
        isLoading: true,
      ),
      _GalleryButton(
        shape: shape,
        intent: ButtonIntent.danger,
        label: 'Delete',
      ),
      _GalleryButton(
        shape: shape,
        intent: ButtonIntent.danger,
        label: 'Delete',
        icon: const Icon(Icons.delete_outline),
      ),
      _GalleryButton(
        shape: shape,
        intent: ButtonIntent.danger,
        label: 'Deleting…',
        isLoading: true,
      ),
      if (shape == _ButtonShape.text)
        _GalleryButton(
          shape: shape,
          intent: ButtonIntent.primary,
          label: 'Disabled',
          disabled: true,
          isCompact: compact,
        ),
    ];
  }
}

enum _ButtonShape { filled, outlined, text }

class _GalleryButton extends StatelessWidget {
  const _GalleryButton({
    required this.shape,
    required this.intent,
    required this.label,
    this.icon,
    this.isLoading = false,
    this.disabled = false,
    this.isCompact = false,
  });

  final _ButtonShape shape;
  final ButtonIntent intent;
  final String label;
  final Widget? icon;
  final bool isLoading;
  final bool disabled;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final onPressed = disabled ? null : () {};
    final child = Text(label);
    switch (shape) {
      case _ButtonShape.filled:
        return SoliplexButton.filled(
          onPressed: onPressed,
          icon: icon,
          intent: intent,
          isLoading: isLoading,
          child: child,
        );
      case _ButtonShape.outlined:
        return SoliplexButton.outlined(
          onPressed: onPressed,
          icon: icon,
          intent: intent,
          isLoading: isLoading,
          child: child,
        );
      case _ButtonShape.text:
        return SoliplexButton.text(
          onPressed: onPressed,
          icon: icon,
          intent: intent,
          isLoading: isLoading,
          isCompact: isCompact,
          child: child,
        );
    }
  }
}

// =====================================================================
// Badges
// =====================================================================

/// Gallery of every `SoliplexBadge` intent. Reused by golden tests.
class BadgeGallery extends StatelessWidget {
  const BadgeGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: 'Label only',
          children: [
            SoliplexBadge(label: Text('Neutral')),
            SoliplexBadge(label: Text('Info'), intent: BadgeIntent.info),
            SoliplexBadge(label: Text('Active'), intent: BadgeIntent.success),
            SoliplexBadge(
              label: Text('Review'),
              intent: BadgeIntent.warning,
            ),
            SoliplexBadge(label: Text('Blocked'), intent: BadgeIntent.danger),
          ],
        ),
        _Section(
          title: 'With leading icon',
          children: [
            SoliplexBadge(label: Text('Draft'), icon: Icon(Icons.edit)),
            SoliplexBadge(
              label: Text('Info'),
              icon: Icon(Icons.info_outline),
              intent: BadgeIntent.info,
            ),
            SoliplexBadge(
              label: Text('Synced'),
              icon: Icon(Icons.check),
              intent: BadgeIntent.success,
            ),
            SoliplexBadge(
              label: Text('Pending'),
              icon: Icon(Icons.schedule),
              intent: BadgeIntent.warning,
            ),
            SoliplexBadge(
              label: Text('Error'),
              icon: Icon(Icons.error_outline),
              intent: BadgeIntent.danger,
            ),
          ],
        ),
      ],
    );
  }
}

// =====================================================================
// Chips
// =====================================================================

/// Gallery of every `SoliplexChip` variant. Reused by golden tests.
///
/// Stateful so filter chips can show both selected and unselected
/// states with a working toggle.
class ChipGallery extends StatefulWidget {
  const ChipGallery({super.key});

  @override
  State<ChipGallery> createState() => _ChipGalleryState();
}

class _ChipGalleryState extends State<ChipGallery> {
  final _filterSelections = <String, bool>{
    'All': true,
    'Active': false,
    'Archived': false,
  };

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Section(
          title: 'Display — label only',
          children: [
            SoliplexChip(label: Text('Neutral')),
            SoliplexChip(label: Text('Info'), intent: ChipIntent.info),
            SoliplexChip(label: Text('Active'), intent: ChipIntent.success),
            SoliplexChip(label: Text('Review'), intent: ChipIntent.warning),
            SoliplexChip(label: Text('Blocked'), intent: ChipIntent.danger),
          ],
        ),
        _Section(
          title: 'Display — with icon and delete',
          children: [
            SoliplexChip(
              label: const Text('Draft'),
              icon: const Icon(Icons.edit),
              onDeleted: () {},
            ),
            SoliplexChip(
              label: const Text('Synced'),
              icon: const Icon(Icons.check),
              intent: ChipIntent.success,
              onDeleted: () {},
            ),
            SoliplexChip(
              label: const Text('Failed'),
              icon: const Icon(Icons.error_outline),
              intent: ChipIntent.danger,
              onDeleted: () {},
            ),
          ],
        ),
        _Section(
          title: 'Action',
          children: [
            SoliplexChip.action(
              label: const Text('Retry'),
              icon: const Icon(Icons.refresh),
              onPressed: () {},
            ),
            SoliplexChip.action(
              label: const Text('Remove'),
              icon: const Icon(Icons.delete_outline),
              intent: ChipIntent.danger,
              onPressed: () {},
            ),
          ],
        ),
        _Section(
          title: 'Filter',
          children: [
            for (final entry in _filterSelections.entries)
              SoliplexChip.filter(
                label: Text(entry.key),
                selected: entry.value,
                onSelected: (v) =>
                    setState(() => _filterSelections[entry.key] = v),
              ),
          ],
        ),
      ],
    );
  }
}

// =====================================================================
// Inputs
// =====================================================================

/// Gallery of every `SoliplexInput` variant. Reused by golden tests.
class InputGallery extends StatelessWidget {
  const InputGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InputSection(
          title: 'Basic',
          child: SoliplexInput(
            label: 'Name',
            hintText: 'Jane Doe',
          ),
        ),
        _InputSection(
          title: 'With leading icon and helper',
          child: SoliplexInput(
            label: 'Email',
            hintText: 'you@example.com',
            helperText: "We'll never share your email.",
            leadingIcon: Icon(Icons.alternate_email),
          ),
        ),
        _InputSection(
          title: 'With error',
          child: SoliplexInput(
            label: 'Email',
            initialValue: 'not-an-email',
            errorText: 'Enter a valid email address.',
            leadingIcon: Icon(Icons.alternate_email),
          ),
        ),
        _InputSection(
          title: 'Password',
          child: SoliplexInput(
            label: 'Password',
            isPassword: true,
            leadingIcon: Icon(Icons.lock_outline),
          ),
        ),
        _InputSection(
          title: 'Loading',
          child: SoliplexInput(
            label: 'Username',
            initialValue: 'jane.doe',
            helperText: 'Checking availability…',
            isLoading: true,
            leadingIcon: Icon(Icons.person_outline),
          ),
        ),
        _InputSection(
          title: 'Disabled',
          child: SoliplexInput(
            label: 'Read-only',
            initialValue: 'cannot change me',
            enabled: false,
          ),
        ),
        _InputSection(
          title: 'Multi-line',
          child: SoliplexInput(
            label: 'Bio',
            hintText: 'Tell us about yourself',
            maxLines: 4,
            minLines: 3,
          ),
        ),
      ],
    );
  }
}

class _InputSection extends StatelessWidget {
  const _InputSection({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: SoliplexSpacing.s2),
          child,
        ],
      ),
    );
  }
}

// =====================================================================
// Dropdowns
// =====================================================================

/// Gallery of every `SoliplexDropdown` variant. Reused by golden tests.
class DropdownGallery extends StatelessWidget {
  const DropdownGallery({super.key});

  static const List<SoliplexDropdownEntry<String>> _planEntries = [
    SoliplexDropdownEntry(value: 'free', label: 'Free'),
    SoliplexDropdownEntry(value: 'pro', label: 'Pro'),
    SoliplexDropdownEntry(value: 'team', label: 'Team'),
  ];

  static const List<SoliplexDropdownEntry<String>> _regionEntries = [
    SoliplexDropdownEntry(
      value: 'eu',
      label: 'Europe',
      icon: Icon(Icons.public),
    ),
    SoliplexDropdownEntry(
      value: 'us',
      label: 'North America',
      icon: Icon(Icons.public),
    ),
    SoliplexDropdownEntry(
      value: 'apac',
      label: 'Asia Pacific',
      icon: Icon(Icons.public),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InputSection(
          title: 'Basic',
          child: SoliplexDropdown<String>(
            label: 'Plan',
            entries: _planEntries,
            initialValue: 'free',
          ),
        ),
        _InputSection(
          title: 'With leading icon and helper',
          child: SoliplexDropdown<String>(
            label: 'Region',
            helperText: 'Where to host your workload.',
            leadingIcon: Icon(Icons.location_on_outlined),
            entries: _regionEntries,
            initialValue: 'eu',
          ),
        ),
        _InputSection(
          title: 'With error',
          child: SoliplexDropdown<String>(
            label: 'Plan',
            errorText: 'Choose a plan to continue.',
            entries: _planEntries,
          ),
        ),
        _InputSection(
          title: 'Loading',
          child: SoliplexDropdown<String>(
            label: 'Region',
            helperText: 'Fetching available regions…',
            isLoading: true,
            entries: _regionEntries,
          ),
        ),
        _InputSection(
          title: 'Disabled',
          child: SoliplexDropdown<String>(
            label: 'Plan',
            enabled: false,
            entries: _planEntries,
            initialValue: 'team',
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Pickers (modal date / time)
// =====================================================================

/// Gallery of the modal date- and time-picker fields. Reused by golden
/// tests.
class PickerGallery extends StatelessWidget {
  const PickerGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InputSection(
          title: 'Date — basic',
          child: SoliplexDatePickerField(
            label: 'Start',
            initialValue: DateTime(2026, 1, 15),
          ),
        ),
        const _InputSection(
          title: 'Date — with helper',
          child: SoliplexDatePickerField(
            label: 'Deadline',
            helperText: 'Pick a date in the future.',
          ),
        ),
        const _InputSection(
          title: 'Date — with error',
          child: SoliplexDatePickerField(
            label: 'Start',
            errorText: 'A start date is required.',
          ),
        ),
        const _InputSection(
          title: 'Date — loading',
          child: SoliplexDatePickerField(
            label: 'Start',
            isLoading: true,
            helperText: 'Checking calendar conflicts…',
          ),
        ),
        const _InputSection(
          title: 'Date — disabled',
          child: SoliplexDatePickerField(
            label: 'Start',
            enabled: false,
          ),
        ),
        const _InputSection(
          title: 'Time — basic',
          child: SoliplexTimePickerField(
            label: 'Reminder',
            initialValue: TimeOfDay(hour: 9, minute: 0),
          ),
        ),
        const _InputSection(
          title: 'Time — disabled',
          child: SoliplexTimePickerField(
            label: 'Reminder',
            enabled: false,
          ),
        ),
      ],
    );
  }
}

// =====================================================================
// Shared
// =====================================================================

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: SoliplexSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: SoliplexSpacing.s2),
          Wrap(
            spacing: SoliplexSpacing.s3,
            runSpacing: SoliplexSpacing.s2,
            children: children,
          ),
        ],
      ),
    );
  }
}
