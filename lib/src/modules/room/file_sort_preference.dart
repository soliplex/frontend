import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'file_sort.dart';

final Logger _logger =
    LogManager.instance.getLogger('soliplex.file_sort_preference');

/// The order every file list in the app shows, as the user last chose it.
///
/// Folders, A to Z is the default, and what a failed read leaves. Storage is
/// best-effort: a failure is logged and never thrown, and the choice still
/// applies for the session. The value is not sensitive, so it lives in
/// shared_preferences.
class FileSortPreference {
  FileSortPreference({Future<SharedPreferences> Function()? prefsFactory})
      : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  static const _key = 'soliplex_file_sort';

  final Signal<FileSort> _sort = Signal<FileSort>(FileSort.foldersAToZ);
  ReadonlySignal<FileSort> get sort => _sort;

  Future<void> load() async {
    try {
      final prefs = await _prefsFactory();
      // A value no longer in [FileSort], left by a renamed one, reads as the
      // default without a record: the reset is how a rename is meant to land.
      final stored = FileSort.values.asNameMap()[prefs.getString(_key)];
      if (stored != null) _sort.value = stored;
    } catch (e, st) {
      // A shared_preferences failure carries no user or backend value.
      _logger.error(
        'Failed to read the file sort; defaulting to folders, A to Z',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Applies [value] at once; returns whether it was saved.
  Future<bool> setSort(FileSort value) async {
    _sort.value = value;
    try {
      final prefs = await _prefsFactory();
      // Android reports a failed commit by returning false, not by throwing.
      final saved = await prefs.setString(_key, value.name);
      if (!saved) _logger.error('Failed to save the file sort');
      return saved;
    } catch (e, st) {
      // A shared_preferences failure carries no user or backend value.
      _logger.error('Failed to save the file sort', error: e, stackTrace: st);
      return false;
    }
  }
}
