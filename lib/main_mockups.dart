import 'package:collection/collection.dart' show IterableExtension;
import 'package:flutter/widgets.dart';

import 'src/mockups/mockup_app.dart';
import 'src/mockups/mockups.dart';

/// Second entry point: the mockup harness instead of the app.
///
///     flutter run -t lib/main_mockups.dart -d linux
///
/// Add `--dart-define=MOCKUP=<name>` to open one mockup straight away, on
/// launch and on every hot restart. No sinks, no auth, no backend — nothing
/// the app boots is needed to draw a screen. See `docs/mockups.md`.
void main() {
  const initial = String.fromEnvironment('MOCKUP');
  runApp(
    MockupApp(
      mockups: mockups,
      initial: mockups.firstWhereOrNull((m) => m.name == initial),
    ),
  );
}
