import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';

/// Finds the [FileName] showing [name].
///
/// [FileName] draws a stem and an extension as two texts, so `find.text`
/// with the whole name matches neither.
Finder findFileName(String name) =>
    find.byWidgetPredicate((w) => w is FileName && w.name == name);
