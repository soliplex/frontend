import 'package:flutter/material.dart';
import 'package:soliplex_design/soliplex_design.dart';

void main() => runApp(const ButtonGalleryApp());

class ButtonGalleryApp extends StatelessWidget {
  const ButtonGalleryApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SoliplexButton Gallery',
      theme: soliplexLightTheme(),
      darkTheme: soliplexDarkTheme(),
      home: const ButtonGalleryScreen(),
    );
  }
}

class ButtonGalleryScreen extends StatefulWidget {
  const ButtonGalleryScreen({super.key});

  @override
  State<ButtonGalleryScreen> createState() => _ButtonGalleryScreenState();
}

class _ButtonGalleryScreenState extends State<ButtonGalleryScreen> {
  ThemeMode _themeMode = ThemeMode.light;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: _themeMode == ThemeMode.light
          ? soliplexLightTheme()
          : soliplexDarkTheme(),
      child: Builder(
        builder: (context) {
          final theme = Theme.of(context);
          return Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: AppBar(
              title: const Text('SoliplexButton'),
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
            body: const SingleChildScrollView(
              padding: EdgeInsets.all(SoliplexSpacing.s4),
              child: ButtonGallery(),
            ),
          );
        },
      ),
    );
  }
}

/// The button gallery as a pure widget, reusable from both the runnable
/// app and from golden tests.
class ButtonGallery extends StatelessWidget {
  const ButtonGallery({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Section(
          title: 'Filled',
          children: _shapeRow(ButtonShape.filled),
        ),
        _Section(
          title: 'Outlined',
          children: _shapeRow(ButtonShape.outlined),
        ),
        _Section(
          title: 'Text',
          children: _shapeRow(ButtonShape.text),
        ),
        _Section(
          title: 'Text — compact',
          children: _shapeRow(ButtonShape.text, compact: true),
        ),
      ],
    );
  }

  List<Widget> _shapeRow(ButtonShape shape, {bool compact = false}) {
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
      if (shape == ButtonShape.text)
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

enum ButtonShape { filled, outlined, text }

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

  final ButtonShape shape;
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
      case ButtonShape.filled:
        return SoliplexButton.filled(
          onPressed: onPressed,
          icon: icon,
          intent: intent,
          isLoading: isLoading,
          child: child,
        );
      case ButtonShape.outlined:
        return SoliplexButton.outlined(
          onPressed: onPressed,
          icon: icon,
          intent: intent,
          isLoading: isLoading,
          child: child,
        );
      case ButtonShape.text:
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
