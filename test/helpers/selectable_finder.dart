import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds the [SelectableRegion]s above [text]: none when no selection area
/// encloses it.
Finder selectionRegionOf(Finder text) =>
    find.ancestor(of: text, matching: find.byType(SelectableRegion));
