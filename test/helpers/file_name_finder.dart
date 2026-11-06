import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workdir_files.dart';

/// Finds the [FileName] showing [name].
///
/// [FileName] draws a name as two texts, the part a cut shortens and the end
/// it keeps, so `find.text` with the whole name matches neither.
Finder findFileName(String name) =>
    find.byWidgetPredicate((w) => w is FileName && w.name == name);

/// Finds the [FolderPath] showing [path].
///
/// [FolderPath] draws a path as up to three texts, the parts a cut gives up
/// in turn, so `find.text` with the whole path matches none.
Finder findFolderPath(String path) =>
    find.byWidgetPredicate((w) => w is FolderPath && w.path == path);
