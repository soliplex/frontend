import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'mockup.dart';

/// A viewport width the harness can pin a mockup to.
///
/// The three constrained values are the `SoliplexBreakpoints` themselves —
/// the widths the adoption checklist asks every screen to behave at, and the
/// exact boundaries where the app's layouts switch.
enum MockupViewport {
  fill(null, 'Fill'),
  mobile(SoliplexBreakpoints.mobile, '320'),
  tablet(SoliplexBreakpoints.tablet, '600'),
  desktop(SoliplexBreakpoints.desktop, '840');

  const MockupViewport(this.width, this.label);

  /// `null` fills the window.
  final double? width;
  final String label;
}

/// The mockup harness: an index of [mockups], each opening in the app's own
/// theme with a toolbar to flip brightness and pin the viewport width.
///
/// The theme is lowered from [brand] the same way `Flavor.build` lowers the
/// standard flavor's, so what a mockup renders here is what it would render
/// in the app. A fork prototypes on its own brand by passing it.
///
/// [initial] opens that mockup over the index at launch — and again after
/// every hot restart, which is what makes it worth setting while iterating on
/// one screen. `main_mockups.dart` reads it from `--dart-define=MOCKUP=<name>`.
class MockupApp extends StatefulWidget {
  const MockupApp({
    super.key,
    required this.mockups,
    this.brand = const BrandTheme.soliplex(),
    this.initial,
  });

  final List<Mockup> mockups;
  final BrandTheme brand;
  final Mockup? initial;

  @override
  State<MockupApp> createState() => _MockupAppState();
}

class _MockupAppState extends State<MockupApp> {
  ThemeMode _mode = ThemeMode.system;
  MockupViewport _viewport = MockupViewport.fill;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: MaterialApp(
        title: 'Soliplex mockups',
        debugShowCheckedModeBanner: false,
        theme: lowerBrandTheme(widget.brand, Brightness.light),
        darkTheme: lowerBrandTheme(widget.brand, Brightness.dark),
        themeMode: _mode,
        // Sits above the navigator so every route — index and mockups alike —
        // can reach the knobs without threading them through constructors.
        builder: (context, child) => _Harness(
          viewport: _viewport,
          onViewport: (v) => setState(() => _viewport = v),
          onThemeMode: (m) => setState(() => _mode = m),
          child: child ?? const SizedBox.shrink(),
        ),
        // Not `home`: the index is the root either way, but [initial] has to
        // be stacked on top of it at launch, and `home` and
        // `onGenerateInitialRoutes` are mutually exclusive.
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => _MockupIndex(mockups: widget.mockups),
        ),
        onGenerateInitialRoutes: (_) => [
          MaterialPageRoute<void>(
            builder: (_) => _MockupIndex(mockups: widget.mockups),
          ),
          if (widget.initial case final mockup?)
            MaterialPageRoute<void>(builder: (_) => _MockupScreen(mockup)),
        ],
      ),
    );
  }
}

/// The harness knobs, reachable from any route via [of].
class _Harness extends InheritedWidget {
  const _Harness({
    required this.viewport,
    required this.onViewport,
    required this.onThemeMode,
    required super.child,
  });

  final MockupViewport viewport;
  final ValueChanged<MockupViewport> onViewport;
  final ValueChanged<ThemeMode> onThemeMode;

  static _Harness of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_Harness>()!;

  @override
  bool updateShouldNotify(_Harness old) => viewport != old.viewport;
}

class _MockupIndex extends StatelessWidget {
  const _MockupIndex({required this.mockups});

  final List<Mockup> mockups;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(
        children: [
          const _Toolbar(title: 'Mockups'),
          Expanded(
            child: mockups.isEmpty
                ? Center(
                    child: Text(
                      'No mockups yet — add one to lib/src/mockups/mockups.dart',
                      style: textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      vertical: SoliplexSpacing.s2,
                    ),
                    itemCount: mockups.length,
                    itemBuilder: (context, i) {
                      final mockup = mockups[i];
                      return ListTile(
                        title: Text(mockup.name),
                        subtitle: mockup.description == null
                            ? null
                            : Text(mockup.description!),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _MockupScreen(mockup),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

/// One open mockup: the toolbar, then the screen in a viewport frame.
class _MockupScreen extends StatelessWidget {
  const _MockupScreen(this.mockup);

  final Mockup mockup;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _Toolbar(title: mockup.name, showViewport: true, showBack: true),
          Expanded(
              child: _ViewportFrame(child: Builder(builder: mockup.build))),
        ],
      ),
    );
  }
}

/// Pins the child to the selected viewport width, overriding `MediaQuery`
/// too: the app reads width through both `LayoutBuilder` and
/// `MediaQuery.sizeOf`, and a frame that only constrained the box would leave
/// the two disagreeing.
class _ViewportFrame extends StatelessWidget {
  const _ViewportFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final width = _Harness.of(context).viewport.width;
    if (width == null) return child;
    final media = MediaQuery.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: SizedBox(
          width: width,
          child: MediaQuery(
            data: media.copyWith(size: Size(width, media.size.height)),
            child: child,
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.title,
    this.showViewport = false,
    this.showBack = false,
  });

  final String title;
  final bool showViewport;
  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final harness = _Harness.of(context);
    final theme = Theme.of(context);
    final isLight = theme.brightness == Brightness.light;
    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SoliplexSpacing.s2,
            vertical: SoliplexSpacing.s1,
          ),
          child: Row(
            children: [
              if (showBack)
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: 'Back to mockups',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              const SizedBox(width: SoliplexSpacing.s2),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (showViewport) ...[
                // Scales down on a narrow toolbar rather than overflowing.
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: SegmentedButton<MockupViewport>(
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: [
                        for (final v in MockupViewport.values)
                          ButtonSegment(value: v, label: Text(v.label)),
                      ],
                      selected: {harness.viewport},
                      onSelectionChanged: (s) => harness.onViewport(s.single),
                    ),
                  ),
                ),
                const SizedBox(width: SoliplexSpacing.s2),
              ],
              IconButton(
                icon: Icon(isLight ? Icons.dark_mode : Icons.light_mode),
                tooltip: isLight ? 'Switch to dark' : 'Switch to light',
                onPressed: () => harness.onThemeMode(
                  isLight ? ThemeMode.dark : ThemeMode.light,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
