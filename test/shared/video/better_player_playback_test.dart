import 'dart:async';

import 'package:better_player/better_player.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/video/better_player_playback.dart';
import 'package:soliplex_frontend/src/shared/video/video_playback.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// The platform side of the player: it creates players and reports their
/// events as the test feeds them.
class _FakePlatform extends BetterPlayerPlatform {
  final events = StreamController<VideoEvent>.broadcast();
  bool disposed = false;

  void started() => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          key: null,
          duration: const Duration(minutes: 1),
          size: const Size(1280, 720),
        ),
      );

  void finished() =>
      events.add(VideoEvent(eventType: VideoEventType.completed, key: null));

  /// The positions the player was asked to seek to, in order.
  final List<Duration?> seeks = [];

  void failed(String message, {String code = 'VideoError'}) => events.addError(
        PlatformException(code: code, message: message),
      );

  @override
  Future<int?> create({BufferingConfiguration? bufferingConfiguration}) async =>
      1;

  @override
  Future<void> setDataSource(int? textureId, DataSource dataSource) async {}

  @override
  Stream<VideoEvent> videoEventsFor(int? textureId) => events.stream;

  @override
  Future<void> dispose(int? textureId) async => disposed = true;

  @override
  Future<void> setLooping(int? textureId, bool looping) async {}

  @override
  Future<void> play(int? textureId) async {}

  @override
  Future<void> pause(int? textureId) async {
    if (refusePause) {
      throw PlatformException(code: 'VideoError', message: 'pause refused');
    }
  }

  /// Makes [pause] fail, as a platform player can.
  bool refusePause = false;

  @override
  Future<void> setVolume(int? textureId, double volume) async {}

  @override
  Future<void> seekTo(int? textureId, Duration? position) async =>
      seeks.add(position);

  @override
  Future<Duration> getPosition(int? textureId) async => Duration.zero;

  @override
  Future<DateTime?> getAbsolutePosition(int? textureId) async => null;

  @override
  Future<void> setSpeed(int? textureId, double speed) async {}

  @override
  Future<void> setTrackParameters(
    int? textureId,
    int? width,
    int? height,
    int? bitrate,
  ) async {}

  @override
  Future<void> setAudioTrack(int? textureId, String? name, int? index) async {}

  @override
  Future<void> setTextTrack(int? textureId, String? name, int? index) async {}

  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) async {}
}

final _signed = Uri.parse('https://cdn.example/clip.mp4?sig=secret');

/// Lets the player's chain of platform calls run to where it waits for the
/// platform to report. Some of better_player's steps wait on more than the
/// test's fake clock drives, so each round also lets real time pass.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();
  }
}

void main() {
  late _FakePlatform platform;

  setUp(() {
    final previous = BetterPlayerPlatform.instance;
    platform = _FakePlatform();
    BetterPlayerPlatform.instance = platform;
    addTearDown(() => BetterPlayerPlatform.instance = previous);
  });

  testWidgets('completes once the video has loaded', (tester) async {
    VideoPlayback? playback;
    VideoStatus? statusOnStart;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {}).then((p) {
        playback = p;
        statusOnStart = p.status.value;
      }),
    );
    await settle(tester);
    expect(playback, isNull, reason: 'nothing has played yet');

    platform.started();
    await settle(tester);

    expect(playback, isNotNull);
    expect(
      statusOnStart!.duration,
      const Duration(minutes: 1),
      reason: 'the status already shows what the start reported',
    );
    playback!.dispose();
  });

  testWidgets('a source that fails to load fails the start, without its query',
      (tester) async {
    Object? failure;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then<void>((_) {}, onError: (Object e) => failure = e),
    );
    await settle(tester);

    platform.failed('HTTP 403 fetching $_signed');
    await settle(tester);

    expect(failure, isA<VideoPlaybackException>());
    final reason = (failure! as VideoPlaybackException).reason;
    expect(reason, contains('HTTP 403'));
    expect(reason, contains('cdn.example/clip.mp4'));
    expect(reason, isNot(contains('secret')));
    expect(platform.disposed, isTrue, reason: 'the failed player is released');
  });

  testWidgets('a player that never starts gives up and is released',
      (tester) async {
    Object? failure;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then<void>((_) {}, onError: (Object e) => failure = e),
    );
    await tester.pump();

    await tester.pump(videoStartLimit - const Duration(seconds: 1));
    expect(failure, isNull);
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);

    expect(failure, isA<VideoPlaybackException>());
    expect(platform.disposed, isTrue);
  });

  testWidgets(
      'a Shaka failure keeps its codes and status, not the response it carries',
      (tester) async {
    Object? failure;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then<void>((_) {}, onError: (Object e) => failure = e),
    );
    await settle(tester);

    // What better_player_web reports when Shaka's request is refused: the
    // whole shaka.util.Error as JSON, its data holding the URL, the status,
    // the response body and the response headers.
    platform.failed(
      code: 'SHAKA_LOAD_ERROR',
      'Failed to load video: shaka.util.Error {\n'
      '  "severity": 2,\n'
      '  "category": 1,\n'
      '  "code": 1001,\n'
      '  "data": [\n'
      '    "https://user:password@cdn.example/clip.m3u8?sig=secret",\n'
      '    403,\n'
      '    "<Error><SignatureProvided>secret</SignatureProvided></Error>",\n'
      '    {"set-cookie": "session=secret"}\n'
      '  ]\n'
      '}',
    );
    await settle(tester);

    final reason = (failure! as VideoPlaybackException).reason;
    expect(reason, contains('SHAKA_LOAD_ERROR'));
    expect(reason, contains('code 1001'));
    expect(reason, contains('HTTP 403'));
    expect(reason, isNot(contains('secret')));
    expect(reason, isNot(contains('password')));
  });

  testWidgets('a URL in a failure keeps its host and path, nothing else',
      (tester) async {
    Object? failure;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then<void>((_) {}, onError: (Object e) => failure = e),
    );
    await settle(tester);

    platform.failed(
      'Cannot Open {NSErrorFailingURLKey=https://user:password@cdn.example'
      ':8443/v/clip.mp4?sig=secret#t=5}',
    );
    await settle(tester);

    final reason = (failure! as VideoPlaybackException).reason;
    expect(reason, contains('https://cdn.example:8443/v/clip.mp4'));
    expect(reason, isNot(contains('password')));
    expect(reason, isNot(contains('secret')));
    expect(reason, isNot(contains('t=5')));
  });

  testWidgets('a failure once playing is reported, without its query',
      (tester) async {
    final reasons = <String>[];
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: reasons.add)
          .then((p) => playback = p),
    );
    await settle(tester);
    platform.started();
    await settle(tester);

    platform.failed('connection lost to $_signed');
    await settle(tester);

    expect(reasons, hasLength(1));
    expect(reasons.single, contains('connection lost'));
    expect(reasons.single, isNot(contains('secret')));
    playback!.dispose();
  });

  testWidgets('playing a finished video starts it from the beginning',
      (tester) async {
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then((p) => playback = p),
    );
    await settle(tester);
    platform.started();
    await settle(tester);
    platform.finished();
    await settle(tester);
    expect(playback!.status.value.isPlaying, isFalse);

    unawaited(playback!.play());
    await settle(tester);

    expect(platform.seeks, contains(Duration.zero));
    playback!.dispose();
  });

  testWidgets('a command the player refuses is logged, not thrown',
      (tester) async {
    final sink = MemorySink();
    LogManager.instance.addSink(sink);
    addTearDown(LogManager.instance.reset);
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then((p) => playback = p),
    );
    await settle(tester);
    platform.started();
    await settle(tester);
    platform.refusePause = true;

    Object? thrown;
    unawaited(playback!.pause().catchError((Object e) => thrown = e));
    await settle(tester);

    expect(thrown, isNull);
    final record = sink.records.singleWhere(
      (r) => r.message == 'A video command failed',
    );
    expect(record.attributes, containsPair('operation', 'pause'));
    expect(record.attributes, containsPair('host', 'cdn.example'));
    expect('${record.attributes}', isNot(contains('secret')));
    // better_player pauses, unawaited, as it disposes.
    platform.refusePause = false;
    playback!.dispose();
  });

  group('qualitiesFrom', () {
    PlayerAsmsTrack track(int height, int bitrate) =>
        PlayerAsmsTrack('$height-$bitrate', 0, height, bitrate, 0, '', '');

    test('lists one quality per height, tallest first, at its best bitrate',
        () {
      final qualities = qualitiesFrom([
        track(360, 800),
        track(720, 2000),
        track(720, 3000),
        track(0, 0),
      ]);

      expect(qualities.keys, [
        720,
        360,
      ]);
      expect(qualities[720]!.bitrate, 3000);
    });

    test('lists none when there is only one height to choose', () {
      expect(qualitiesFrom([track(720, 2000), track(720, 3000)]), isEmpty);
    });
  });
}
