import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart'
    show SoliplexSpacing, soliplexLightTheme;
import 'package:soliplex_frontend/src/shared/video/video_controls.dart';
import 'package:soliplex_frontend/src/shared/video/video_playback.dart';

/// Plays as a player would: every command shows in [status], which tests also
/// set directly.
class _FakePlayback implements VideoPlayback {
  @override
  final Signal<VideoStatus> status = signal(
    const VideoStatus(
      isPlaying: true,
      position: Duration(seconds: 5),
      duration: Duration(minutes: 1, seconds: 30),
    ),
  );

  static const _keep = Object();

  /// Changes the fields given, keeping the rest. [duration] and [quality]
  /// take null as a value, so leaving them out is told apart by [_keep].
  void set({
    Duration? position,
    Object? duration = _keep,
    bool? isPlaying,
    double? volume,
    List<int>? qualities,
    Object? quality = _keep,
  }) {
    final s = status.value;
    status.value = VideoStatus(
      position: position ?? s.position,
      duration: identical(duration, _keep) ? s.duration : duration as Duration?,
      isPlaying: isPlaying ?? s.isPlaying,
      volume: volume ?? s.volume,
      qualities: qualities ?? s.qualities,
      quality: identical(quality, _keep) ? s.quality : quality as int?,
    );
  }

  @override
  Future<void> play() async => set(isPlaying: true);

  @override
  Future<void> pause() async => set(isPlaying: false);

  @override
  Future<void> seekTo(Duration position) async => set(position: position);

  @override
  Future<void> setVolume(double volume) async => set(volume: volume);

  @override
  void selectQuality(int? height) => set(quality: height);

  @override
  Widget buildView() => const SizedBox.expand();

  @override
  void dispose() {}
}

const _hd = 720;
const _sd = 360;

void main() {
  late _FakePlayback playback;

  setUp(() => playback = _FakePlayback());

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
    expect(playback.status.value.isPlaying, isFalse);
    expect(find.byTooltip('Play'), findsOneWidget);
    await tester.tap(find.byTooltip('Play'));
    await tester.pump();

    expect(playback.status.value.isPlaying, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);
  });

  testWidgets('shows hours once a video runs an hour', (tester) async {
    playback.set(
      position: const Duration(hours: 1, minutes: 2, seconds: 3),
      duration: const Duration(hours: 2),
    );
    await pump(tester);

    expect(find.text('1:02:03 / 2:00:00'), findsOneWidget);
  });

  testWidgets('mutes and restores the volume it had', (tester) async {
    playback.set(volume: 0.6);
    await pump(tester);

    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(playback.status.value.volume, 0);
    expect(find.byTooltip('Unmute'), findsOneWidget);
    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();

    expect(playback.status.value.volume, 0.6);
  });

  testWidgets('dragging the progress bar shows the time, then seeks',
      (tester) async {
    await pump(tester);
    final bar = tester.getRect(find.byType(Slider));

    final drag =
        await tester.startGesture(bar.centerLeft + const Offset(40, 0));
    await tester.pump();
    await drag.moveTo(bar.center - const Offset(20, 0));
    await tester.pump();
    await drag.moveTo(bar.center);
    await tester.pump();
    expect(
      playback.status.value.position,
      const Duration(seconds: 5),
      reason: 'no seek until the drag ends',
    );
    expect(find.textContaining(RegExp(r'^0:4\d / 1:30$')), findsOneWidget);

    await drag.up();
    await tester.pump();
    expect(
      playback.status.value.position.inSeconds,
      closeTo(45, 3),
    );
  });

  testWidgets('a video of unknown length shows only where it is',
      (tester) async {
    playback.set(duration: null);
    await pump(tester);

    expect(find.text('0:05'), findsOneWidget);
    expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);
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

    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('Quality'));
      await tester.pumpAndSettle();
    }

    bool checked(String label) =>
        tester.widget<CheckedPopupMenuItem<int>>(item(label)).checked;

    await openMenu();
    expect(checked('Auto'), isTrue);
    await tester.tap(item('360p'));
    await tester.pumpAndSettle();

    expect(playback.status.value.quality, _sd);
    await openMenu();
    expect(checked('360p'), isTrue);
    expect(checked('Auto'), isFalse);
    await tester.tap(item('Auto'));
    await tester.pumpAndSettle();

    expect(playback.status.value.quality, isNull);
    await openMenu();
    expect(checked('Auto'), isTrue);
  });

  group('a tap on the video', () {
    Future<void> tapVideo(WidgetTester tester, PointerDeviceKind kind) async {
      await tester.tapAt(
        tester.getRect(find.byType(VideoControls)).topCenter +
            const Offset(0, 20),
        kind: kind,
      );
      await tester.pump();
    }

    testWidgets('by mouse pauses and plays', (tester) async {
      await pump(tester);

      await tapVideo(tester, PointerDeviceKind.mouse);
      expect(playback.status.value.isPlaying, isFalse);
      await tapVideo(tester, PointerDeviceKind.mouse);
      expect(playback.status.value.isPlaying, isTrue);
    });

    testWidgets('by touch on a hidden Pause button only shows the controls',
        (tester) async {
      await pump(tester);
      final pause = tester.getCenter(find.byTooltip('Pause'));
      await tapVideo(tester, PointerDeviceKind.touch);
      expect(railOpacity(tester), 0);

      await tester.tapAt(pause, kind: PointerDeviceKind.touch);
      await tester.pump();

      expect(playback.status.value.isPlaying, isTrue);
      expect(railOpacity(tester), 1);
    });

    testWidgets('by touch hides and shows the controls, never pausing',
        (tester) async {
      await pump(tester);

      await tapVideo(tester, PointerDeviceKind.touch);
      expect(railOpacity(tester), 0);
      await tapVideo(tester, PointerDeviceKind.touch);
      expect(railOpacity(tester), 1);

      expect(playback.status.value.isPlaying, isTrue);
    });
  });
}
