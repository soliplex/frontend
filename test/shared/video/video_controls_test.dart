import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart'
    show SoliplexSpacing, soliplexLightTheme;
import 'package:soliplex_frontend/src/shared/video/video_controls.dart';
import 'package:soliplex_frontend/src/shared/video/video_playback.dart';

/// Records what the controls ask of the player; tests set [status].
class _RecordingPlayback implements VideoPlayback {
  @override
  final Signal<VideoStatus> status = signal(
    const VideoStatus(
      isPlaying: true,
      position: Duration(seconds: 5),
      duration: Duration(minutes: 1, seconds: 30),
    ),
  );

  final List<String> calls = [];

  void set({
    bool? isPlaying,
    double? volume,
    List<VideoQuality>? qualities,
    VideoQuality? quality,
  }) {
    final s = status.value;
    status.value = VideoStatus(
      position: s.position,
      duration: s.duration,
      isPlaying: isPlaying ?? s.isPlaying,
      volume: volume ?? s.volume,
      qualities: qualities ?? s.qualities,
      quality: quality ?? s.quality,
    );
  }

  @override
  bool get isPlaying => status.value.isPlaying;

  @override
  Future<void> play() async {
    calls.add('play');
    set(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    set(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async =>
      calls.add('seek ${position.inSeconds}');

  @override
  Future<void> setVolume(double volume) async {
    calls.add('volume $volume');
    set(volume: volume);
  }

  @override
  void selectQuality(VideoQuality? quality) =>
      calls.add('quality ${quality?.label ?? 'auto'}');

  @override
  Widget buildView() => const SizedBox.expand();

  @override
  void dispose() {}
}

const _hd = VideoQuality(label: '720p', id: 720);
const _sd = VideoQuality(label: '360p', id: 360);

void main() {
  late _RecordingPlayback playback;

  setUp(() => playback = _RecordingPlayback());

  Future<void> pump(
    WidgetTester tester, {
    VideoHostActions actions = const VideoHostActions(),
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Center(
            child: SizedBox(
              width: 480,
              height: 270,
              child: VideoControls(playback: playback, actions: actions),
            ),
          ),
        ),
      );

  Finder item(String label) =>
      find.widgetWithText(CheckedPopupMenuItem<int>, label);

  double railOpacity(WidgetTester tester) =>
      tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

  testWidgets('plays, pauses and shows the time', (tester) async {
    await pump(tester);

    expect(find.text('0:05 / 1:30'), findsOneWidget);
    await tester.tap(find.byTooltip('Pause'));
    await tester.pump();
    expect(find.byTooltip('Play'), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    expect(playback.calls, ['pause', 'play']);
  });

  testWidgets('mutes and restores the volume it had', (tester) async {
    playback.set(volume: 0.6);
    await pump(tester);

    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();

    expect(playback.calls, ['volume 0.0', 'volume 0.6']);
  });

  testWidgets('dragging the progress bar seeks', (tester) async {
    await pump(tester);

    final bar = tester.getRect(find.byType(Slider));
    await tester.tapAt(bar.center);
    await tester.pump();

    expect(playback.calls.single, startsWith('seek '));
    final seconds = int.parse(playback.calls.single.split(' ').last);
    expect(seconds, closeTo(45, 3));
  });

  testWidgets('hides while playing and comes back on hover', (tester) async {
    await pump(tester);
    expect(railOpacity(tester), 1);

    await tester.pump(VideoControls.hideAfter);
    expect(railOpacity(tester), 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(find.byType(Stack)));
    await mouse.moveBy(const Offset(4, 4));
    await tester.pump();
    expect(railOpacity(tester), 1);
    await mouse.removePointer();
  });

  testWidgets('stays while paused', (tester) async {
    playback.set(isPlaying: false);
    await pump(tester);

    await tester.pump(VideoControls.hideAfter * 2);

    expect(railOpacity(tester), 1);
  });

  testWidgets('offers only the moves its host has', (tester) async {
    await pump(tester, actions: VideoHostActions(enterFullscreen: () {}));

    expect(find.byTooltip('Full screen'), findsOneWidget);
    expect(find.byTooltip('Expand video'), findsNothing);
    expect(find.byTooltip('Exit full screen'), findsNothing);
  });

  testWidgets('the moves sit at the right end of the rail', (tester) async {
    await pump(
      tester,
      actions: VideoHostActions(expand: () {}, enterFullscreen: () {}),
    );

    final rail = tester.getRect(find.byType(VideoControls));
    final last = tester.getRect(find.byTooltip('Full screen'));
    final expand = tester.getRect(find.byTooltip('Expand video'));
    expect(rail.right - last.right, lessThan(SoliplexSpacing.s4));
    expect(expand.right, lessThanOrEqualTo(last.left + 1));
  });

  testWidgets('a plain file has no quality menu', (tester) async {
    await pump(tester);

    expect(find.byTooltip('Quality'), findsNothing);
  });

  testWidgets('a stream can be pinned to a quality and set back to auto',
      (tester) async {
    playback.set(qualities: const [_hd, _sd]);
    await pump(tester);

    await tester.tap(find.byTooltip('Quality'));
    await tester.pumpAndSettle();
    expect(find.text('Auto'), findsOneWidget);
    await tester.tap(item('360p'));
    await tester.pumpAndSettle();

    playback.set(quality: _sd);
    await tester.pump();
    await tester.tap(find.byTooltip('Quality'));
    await tester.pumpAndSettle();
    await tester.tap(item('Auto'));
    await tester.pumpAndSettle();

    expect(playback.calls, ['quality 360p', 'quality auto']);
  });
}
