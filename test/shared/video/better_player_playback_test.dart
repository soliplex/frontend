import 'dart:async';

import 'package:better_player/better_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:soliplex_frontend/src/shared/video/better_player_playback.dart';
import 'package:soliplex_frontend/src/shared/video/video_card.dart';
import 'package:soliplex_frontend/src/shared/video/video_playback.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// The platform side of the player: it creates players and reports their
/// events as the test feeds them.
class _FakePlatform extends BetterPlayerPlatform {
  final events = StreamController<VideoEvent>.broadcast();
  bool disposed = false;

  void started({Size size = const Size(1280, 720)}) => events.add(
        VideoEvent(
          eventType: VideoEventType.initialized,
          key: null,
          duration: const Duration(minutes: 1),
          size: size,
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

  /// Whether the player was last told to play rather than pause.
  bool playing = false;

  @override
  Future<void> play(int? textureId) async {
    if (refusePlay) {
      throw PlatformException(code: 'VideoError', message: 'play refused');
    }
    playing = true;
  }

  /// Makes [play] fail, as a platform player can.
  bool refusePlay = false;

  @override
  Future<void> pause(int? textureId) async {
    if (refusePause) {
      // A platform's error text can name the source.
      throw PlatformException(code: 'VideoError', message: 'refused $_signed');
    }
    playing = false;
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

  /// The heights the player was asked to keep to, in order.
  final List<int?> trackHeights = [];

  @override
  Future<void> setTrackParameters(
    int? textureId,
    int? width,
    int? height,
    int? bitrate,
  ) async =>
      trackHeights.add(height);

  @override
  Future<void> setAudioTrack(int? textureId, String? name, int? index) async {}

  @override
  Future<void> setTextTrack(int? textureId, String? name, int? index) async {}

  @override
  Future<void> setMixWithOthers(int? textureId, bool mixWithOthers) async {}

  @override
  Widget buildView(int? textureId) => const _PlatformView();
}

/// Stands in for the platform view; a new one of these is a new view.
class _PlatformView extends StatefulWidget {
  const _PlatformView();

  @override
  State<_PlatformView> createState() => _PlatformViewState();
}

class _PlatformViewState extends State<_PlatformView> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

final _signed = Uri.parse('https://cdn.example/clip.mp4?sig=secret');

const _box = ValueKey('box');

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
    expect(reason, contains('request https://cdn.example/clip.m3u8'));
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
      ':8443/v/clip.mp4?exp=1,sig=secret#t=5}',
    );
    await settle(tester);

    final reason = (failure! as VideoPlaybackException).reason;
    expect(reason, contains('https://cdn.example:8443/v/clip.mp4'));
    expect(reason, isNot(contains('password')));
    expect(reason, isNot(contains('secret')));
    expect(reason, isNot(contains('t=5')));
  });

  testWidgets('a failure right as the video loads is still reported',
      (tester) async {
    final events = <String>[];
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: events.add).then((p) {
        playback = p;
        events.add('started');
      }),
    );
    await settle(tester);

    // better_player stops listening for errors as it finishes initialising
    // the video, after the start has completed; this one lands then.
    platform
      ..started()
      ..failed('segment refused: $_signed');
    await settle(tester);

    expect(events, hasLength(2));
    expect(events.first, 'started', reason: 'the card ignores errors before');
    expect(events.last, contains('segment refused'));
    expect(events.last, isNot(contains('secret')));
    playback!.dispose();
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

  testWidgets('a finished video stops the player wanting to play',
      (tester) async {
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then((p) => playback = p),
    );
    await settle(tester);
    platform.started();
    await settle(tester);
    expect(platform.playing, isTrue);

    platform.finished();
    await settle(tester);

    // Android's player, left set to play, would resume on the next seek
    // while the status says paused.
    expect(platform.playing, isFalse);
    playback!.dispose();
  });

  testWidgets('the player outlives the views it moves between', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VideoCard(
            uri: _signed,
            playbackFactory: createBetterPlayerPlayback,
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Play video'));
    await settle(tester);
    platform.started();
    await settle(tester);

    // Each move unmounts the view it leaves; only the card releases the
    // player.
    await tester.tap(find.byTooltip('Expand video'));
    await settle(tester);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);

    expect(platform.disposed, isFalse);
    expect(find.byTooltip('Expand video'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
    expect(platform.disposed, isTrue, reason: 'the card releases it');
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
    expect(record.attributes['failure'], contains('cdn.example/clip.mp4'));
    expect('${record.attributes}', isNot(contains('secret')));
    // better_player's own dispose pauses without awaiting, so a refused
    // pause there would be an uncaught error.
    platform.refusePause = false;
    playback!.dispose();
  });

  testWidgets('a refused play or pause leaves the status as the player is',
      (tester) async {
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then((p) => playback = p),
    );
    await settle(tester);
    platform.started();
    await settle(tester);
    expect(playback!.status.value.isPlaying, isTrue);

    platform.refusePause = true;
    unawaited(playback!.pause());
    await settle(tester);
    expect(playback!.status.value.isPlaying, isTrue, reason: 'still playing');

    platform
      ..refusePause = false
      ..refusePlay = false;
    unawaited(playback!.pause());
    await settle(tester);
    platform.refusePlay = true;
    unawaited(playback!.play());
    await settle(tester);
    expect(playback!.status.value.isPlaying, isFalse, reason: 'still paused');

    platform.refusePlay = false;
    playback!.dispose();
  });

  testWidgets('its status follows what the player reports', (tester) async {
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then((p) => playback = p),
    );
    await settle(tester);
    platform.started();
    await settle(tester);

    void report(VideoEventType type, {List<DurationRange>? buffered}) =>
        platform.events.add(
          VideoEvent(eventType: type, key: null, buffered: buffered),
        );

    report(VideoEventType.pause);
    await settle(tester);
    expect(playback!.status.value.isPlaying, isFalse);

    report(VideoEventType.play);
    report(VideoEventType.bufferingStart);
    report(
      VideoEventType.bufferingUpdate,
      buffered: [
        DurationRange(Duration.zero, const Duration(seconds: 10)),
        DurationRange(
          const Duration(seconds: 20),
          const Duration(seconds: 35),
        ),
        DurationRange(
          const Duration(seconds: 12),
          const Duration(seconds: 15),
        ),
      ],
    );
    await settle(tester);

    final status = playback!.status.value;
    expect(status.isPlaying, isTrue);
    expect(status.isBuffering, isTrue);
    expect(
      status.buffered,
      const Duration(seconds: 35),
      reason: 'the furthest any range reaches',
    );
    playback!.dispose();
  });

  testWidgets(
      'an HLS stream offers its renditions, and keeps to the chosen one',
      (tester) async {
    const master = '''
#EXTM3U
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360
360.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720
720.m3u8
''';
    VideoPlayback? playback;
    http.runWithClient(
      () => unawaited(
        createBetterPlayerPlayback(
          Uri.parse('https://cdn.example/stream.m3u8'),
          onError: (_) {},
        ).then((p) => playback = p),
      ),
      () => MockClient((_) async => http.Response(master, 200)),
    );
    await settle(tester);
    platform.started();
    await settle(tester);

    expect(
      playback!.status.value.qualities,
      [720, 360],
    );

    playback!.selectQuality(720);
    await settle(tester);
    expect(playback!.status.value.quality, 720);
    expect(platform.trackHeights.last, 720);

    playback!.selectQuality(null);
    await settle(tester);
    expect(playback!.status.value.quality, isNull);
    expect(platform.trackHeights.last, 0, reason: 'no limit: adaptive again');
    playback!.dispose();
  });

  /// Starts a playback, reporting [size] as the start does, and shows its
  /// view in a 320 by 180 box.
  Future<VideoPlayback> startShown(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    VideoPlayback? playback;
    unawaited(
      createBetterPlayerPlayback(_signed, onError: (_) {})
          .then((p) => playback = p),
    );
    await settle(tester);
    platform.started(size: size);
    await settle(tester);
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            key: _box,
            width: 320,
            height: 180,
            child: playback!.buildView(),
          ),
        ),
      ),
    );
    await settle(tester);
    return playback!;
  }

  testWidgets('its view outlives the video size arriving', (tester) async {
    // Safari reports no size until the first frame has been decoded.
    final playback = await startShown(tester, size: Size.zero);
    final view = tester.state(find.byType(_PlatformView));

    platform.events.add(
      VideoEvent(
        eventType: VideoEventType.changedSize,
        key: null,
        size: const Size(1280, 720),
      ),
    );
    await settle(tester);

    // A new platform view moves the <video> element, which pauses it.
    expect(tester.state(find.byType(_PlatformView)), same(view));
    playback.dispose();
  });

  testWidgets('a video of another shape fits inside its view', (tester) async {
    final playback = await startShown(tester, size: const Size(640, 480));

    final view = tester.getRect(find.byType(_PlatformView));
    expect(view.size, const Size(240, 180));
    expect(view.center, tester.getCenter(find.byKey(_box)));
    playback.dispose();
  });

  testWidgets('plays while the app is inactive', (tester) async {
    addTearDown(
      () => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    final playback = await startShown(tester);
    unawaited(playback.pause());
    await settle(tester);

    // Safari blurs the window as Escape leaves its full screen, while the
    // video moves back to the view it left.
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    unawaited(playback.play());
    await settle(tester);

    expect(platform.playing, isTrue);
    playback.dispose();
  });

  testWidgets('going to the background pauses it', (tester) async {
    addTearDown(
      () => tester.binding
          .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
    );
    final playback = await startShown(tester);
    expect(platform.playing, isTrue);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);

    expect(platform.playing, isFalse);
    expect(playback.status.value.isPlaying, isFalse);
    playback.dispose();
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
