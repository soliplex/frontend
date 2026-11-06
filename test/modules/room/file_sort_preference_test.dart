import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/file_sort_preference.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Storage that refuses the write without throwing, as Android does when
/// `commit()` fails.
class _RefusingPrefs extends Fake implements SharedPreferences {
  @override
  Future<bool> setString(String key, String value) async => false;
}

/// Captures this preference's error records for the test.
Iterable<LogRecord> Function() _captureErrors() {
  final sink = MemorySink();
  LogManager.instance.addSink(sink);
  addTearDown(() => LogManager.instance.removeSink(sink));
  return () => sink.records.where(
        (r) =>
            r.level == LogLevel.error &&
            r.loggerName == 'soliplex.file_sort_preference',
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('defaults to folders, A to Z', () async {
    final errors = _captureErrors();
    final preference = FileSortPreference();

    await preference.load();

    expect(preference.sort.value, FileSort.foldersAToZ);
    expect(errors(), isEmpty);
  });

  test('loads a stored choice', () async {
    SharedPreferences.setMockInitialValues(
      {'soliplex_file_sort': 'smallestFirst'},
    );
    final preference = FileSortPreference();

    await preference.load();

    expect(preference.sort.value, FileSort.smallestFirst);
  });

  test('an unknown stored value reads as the default', () async {
    SharedPreferences.setMockInitialValues({'soliplex_file_sort': 'bogus'});
    final errors = _captureErrors();
    final preference = FileSortPreference();

    await preference.load();

    expect(preference.sort.value, FileSort.foldersAToZ);
    expect(errors(), isEmpty, reason: 'a renamed value resets silently');
  });

  test('a failed read leaves the default and logs', () async {
    final errors = _captureErrors();
    final preference = FileSortPreference(
      prefsFactory: () => Future.error(StateError('prefs unavailable')),
    );

    await preference.load();

    expect(preference.sort.value, FileSort.foldersAToZ);
    expect(errors(), hasLength(1));
  });

  test('setSort applies at once and persists', () async {
    final preference = FileSortPreference();

    final saving = preference.setSort(FileSort.newestFirst);

    expect(preference.sort.value, FileSort.newestFirst);
    expect(await saving, isTrue);
    final reloaded = FileSortPreference();
    await reloaded.load();
    expect(reloaded.sort.value, FileSort.newestFirst);
  });

  test('a refused save still applies for the session and logs', () async {
    final errors = _captureErrors();
    final preference = FileSortPreference(
      prefsFactory: () async => _RefusingPrefs(),
    );

    final saved = await preference.setSort(FileSort.largestFirst);

    expect(saved, isFalse);
    expect(preference.sort.value, FileSort.largestFirst);
    expect(errors().single.attributes, {'sort': 'largestFirst'});
  });

  test('a save that throws still applies for the session and logs', () async {
    final errors = _captureErrors();
    final preference = FileSortPreference(
      prefsFactory: () => Future.error(StateError('prefs unavailable')),
    );

    final saved = await preference.setSort(FileSort.oldestFirst);

    expect(saved, isFalse);
    expect(preference.sort.value, FileSort.oldestFirst);
    final record = errors().single;
    expect(record.attributes, {'sort': 'oldestFirst'});
    expect(record.error, isA<StateError>());
    expect(record.stackTrace, isNotNull);
  });
}
