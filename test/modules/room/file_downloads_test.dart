import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'package:soliplex_frontend/src/modules/room/file_downloads.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

void main() {
  final a = _file('a.csv');
  final b = _file('b.csv');

  test('a download shows under way, then its save for 2 s, then idle', () {
    fakeAsync((async) {
      final pending = Completer<DownloadOutcome>();
      final downloads = FileDownloads((_, __) => pending.future);
      addTearDown(downloads.dispose);

      downloads.start(a);
      expect(downloads.stateOf(a), const DownloadRunning());
      expect(downloads.stateOf(b), const DownloadIdle());

      pending.complete(const DownloadSaved());
      async.flushMicrotasks();
      expect(downloads.stateOf(a), const DownloadSaved());

      async.elapse(const Duration(milliseconds: 1999));
      expect(downloads.stateOf(a), const DownloadSaved());
      async.elapse(const Duration(milliseconds: 1));
      expect(downloads.stateOf(a), const DownloadIdle());
    });
  });

  test('a failed download shows its failure and its reason', () {
    fakeAsync((async) {
      final downloads = FileDownloads(
        (_, __) async => const DownloadFailed("File isn't available anymore"),
      );
      addTearDown(downloads.dispose);

      downloads.start(a);
      async.flushMicrotasks();

      expect(
        downloads.stateOf(a),
        isA<DownloadFailed>()
            .having((f) => f.reason, 'reason', "File isn't available anymore"),
      );
    });
  });

  test('a failure shows until a retry starts', () {
    fakeAsync((async) {
      var runs = 0;
      final downloads = FileDownloads((_, __) async {
        runs++;
        return const DownloadFailed("File isn't available anymore");
      });
      addTearDown(downloads.dispose);

      downloads.start(a);
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 1));
      expect(downloads.stateOf(a), isA<DownloadFailed>());

      downloads.start(a);
      expect(downloads.stateOf(a), const DownloadRunning());
      async.flushMicrotasks();
      expect(runs, 2);
    });
  });

  test('a cancelled save goes straight back to idle', () {
    fakeAsync((async) {
      final downloads =
          FileDownloads((_, __) async => const DownloadCancelled());
      addTearDown(downloads.dispose);

      downloads.start(a);
      async.flushMicrotasks();

      expect(downloads.stateOf(a), const DownloadIdle());
    });
  });

  test('a file starts no second download while one runs or its save shows', () {
    fakeAsync((async) {
      final pending = Completer<DownloadOutcome>();
      final started = <String>[];
      final downloads = FileDownloads((file, _) {
        started.add(file.filename);
        return pending.future;
      });
      addTearDown(downloads.dispose);

      downloads
        ..start(a)
        ..start(a)
        ..start(b);
      expect(started, ['a.csv', 'b.csv']);

      pending.complete(const DownloadSaved());
      async.flushMicrotasks();
      downloads.start(a);
      expect(started, ['a.csv', 'b.csv'], reason: 'its save still shows');

      async.elapse(const Duration(seconds: 2));
      downloads.start(a);
      expect(started, ['a.csv', 'b.csv', 'a.csv']);
    });
  });

  test('a download that throws shows a failure and is logged', () {
    fakeAsync((async) {
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));
      final downloads =
          FileDownloads((_, __) async => throw StateError('broken'));
      addTearDown(downloads.dispose);

      downloads.start(a);
      async.flushMicrotasks();

      expect(
        downloads.stateOf(a),
        isA<DownloadFailed>()
            .having((f) => f.reason, 'reason', 'Something went wrong'),
      );
      final record = sink.records.singleWhere(
        (r) => r.level == LogLevel.error,
      );
      expect(record.message, 'workdir download threw');
      expect(record.attributes['filename'], 'a.csv');
      expect(record.attributes['failure'], isNotNull);
      expect(record.error, isNull, reason: 'its text may carry anything');
      expect(
        record.attributes.values.whereType<String>(),
        everyElement(isNot(contains('broken'))),
      );
    });
  });

  test('a file the listing reports anew keeps its download', () {
    fakeAsync((async) {
      final pending = Completer<DownloadOutcome>();
      final started = <WorkdirFile>[];
      final downloads = FileDownloads((file, _) {
        started.add(file);
        return pending.future;
      });
      addTearDown(downloads.dispose);
      final rewritten = WorkdirFile(
        filename: a.filename,
        url: a.url,
        modifiedAt: DateTime.utc(2026, 11, 6),
        sizeBytes: 42,
      );

      downloads
        ..start(a)
        ..start(rewritten);
      expect(started, [a], reason: 'it is the same file, still downloading');
      expect(downloads.stateOf(rewritten), const DownloadRunning());

      pending.complete(const DownloadFailed("File isn't available anymore"));
      async.flushMicrotasks();
      expect(downloads.stateOf(rewritten), isA<DownloadFailed>());
    });
  });

  test('tells a download once its downloads are cleared', () {
    fakeAsync((async) {
      late bool Function() isCleared;
      final downloads = FileDownloads((_, cleared) {
        isCleared = cleared;
        return Completer<DownloadOutcome>().future;
      })
        ..start(a);
      expect(isCleared(), isFalse);

      downloads.dispose();

      expect(isCleared(), isTrue);
    });
  });

  test('a download started once cleared is recorded, not run', () {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    final level = LogManager.instance.minimumLevel;
    LogManager.instance.minimumLevel = LogLevel.debug;
    addTearDown(() {
      LogManager.instance.minimumLevel = level;
      LogManager.instance.removeSink(sink);
    });
    final started = <WorkdirFile>[];
    final downloads = FileDownloads((file, _) async {
      started.add(file);
      return const DownloadSaved();
    })
      ..dispose();

    expect(downloads.start(a), completes);
    expect(started, isEmpty);
    expect(
      sink.records.map((r) => r.message),
      contains(startsWith('download not started, its downloads cleared')),
    );
  });

  test('a download under way reads as idle once its downloads are cleared', () {
    fakeAsync((async) {
      final downloads = FileDownloads(
        (_, __) => Completer<DownloadOutcome>().future,
      )..start(a);
      expect(downloads.stateOf(a), const DownloadRunning());

      downloads.dispose();

      expect(downloads.stateOf(a), const DownloadIdle());
    });
  });

  test('a download ending after dispose shows nothing', () {
    fakeAsync((async) {
      final pending = Completer<DownloadOutcome>();
      final downloads = FileDownloads((_, __) => pending.future)..start(a);

      downloads.dispose();
      pending.complete(const DownloadSaved());
      async.flushMicrotasks();

      expect(downloads.stateOf(a), const DownloadIdle());
      expect(async.pendingTimers, isEmpty);
    });
  });

  test('dispose cancels an outcome waiting to clear', () {
    fakeAsync((async) {
      final downloads = FileDownloads((_, __) async => const DownloadSaved())
        ..start(a);
      async.flushMicrotasks();

      downloads.dispose();

      expect(async.pendingTimers, isEmpty);
    });
  });
}
