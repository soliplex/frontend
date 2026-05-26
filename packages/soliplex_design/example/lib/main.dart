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
