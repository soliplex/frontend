import 'package:flutter/widgets.dart';

/// One prototype screen the mockup harness can open.
///
/// [build] returns the whole screen — usually a `Scaffold` — exactly as it
/// would sit in the app. The harness supplies everything around it: the brand
/// theme in both brightnesses, a `ProviderScope`, and a viewport that can be
/// pinned to each `SoliplexBreakpoints` width.
///
/// Keep the screen itself in its own widget class and make [build] a one-line
/// constructor call, so a hot reload after editing the screen lands on the
/// route that is already open.
class Mockup {
  const Mockup({required this.name, required this.build, this.description});

  /// Shown in the index and the harness toolbar.
  final String name;

  /// One line under the name in the index, if there is something to say.
  final String? description;

  final WidgetBuilder build;
}
