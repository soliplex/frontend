import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart' show soliplexLightTheme;
import 'package:soliplex_frontend/src/shared/video/video_card.dart';
import 'package:soliplex_frontend/src/shared/video/video_playback.dart';

/// Stands in for the platform player: a playing flag, a count of resumes, and
/// a view tests can find.
class _FakePlayback implements VideoPlayback {
  bool playing = true;
  int plays = 0;
  bool disposed = false;

  @override
  final Signal<VideoStatus> status = signal(const VideoStatus(isPlaying: true));

  @override
  bool get isPlaying => playing;

  @override
  Future<void> play() async {
    plays++;
    playing = true;
  }

  @override
  Future<void> pause() async => playing = false;

  @override
  Future<void> seekTo(Duration position) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  void selectQuality(VideoQuality? quality) {}

  @override
  Widget buildView() => const SizedBox.expand(key: _viewKey);

  @override
  void dispose() => disposed = true;
}

const _viewKey = ValueKey('video-view');
final _uri = Uri.parse('https://cdn.example/clip.mp4');

void main() {
  late _FakePlayback playback;
  late int created;
  VoidCallback? reportError;

  setUp(() {
    playback = _FakePlayback();
    created = 0;
    reportError = null;
  });

  Future<VideoPlayback> factory(
    Uri uri, {
    required VoidCallback onError,
  }) async {
    created++;
    reportError = onError;
    return playback;
  }

  Future<void> pumpCard(WidgetTester tester, {String? caption}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: VideoCard(
                  uri: _uri,
                  caption: caption,
                  playbackFactory: factory,
                ),
              ),
            ),
          ),
        ),
      );

  Future<void> startPlaying(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Play video'));
    await tester.pumpAndSettle();
  }

  testWidgets('is message-wide and 16:9 before anything loads', (tester) async {
    await pumpCard(tester, caption: 'A demo');

    final size = tester.getSize(find.byType(AspectRatio));
    expect(size.width, 400);
    expect(size.height, closeTo(400 * 9 / 16, 0.01));
    expect(find.text('A demo'), findsOneWidget);
    expect(created, 0, reason: 'nothing loads until the user presses play');
  });

  testWidgets('pressing play starts the player inline', (tester) async {
    await pumpCard(tester);

    await startPlaying(tester);

    expect(created, 1);
    expect(find.byKey(_viewKey), findsOneWidget);
    expect(find.byTooltip('Expand video'), findsOneWidget);
  });

  testWidgets('expanding hands the view to the dialog and keeps it playing',
      (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);

    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    // One view, in the dialog; the card says where the video went.
    expect(find.byKey(_viewKey), findsOneWidget);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.byKey(_viewKey)),
      findsOneWidget,
    );
    expect(find.text('Playing in the expanded view'), findsOneWidget);
    expect(playback.plays, 1, reason: 'resumed after the move');
  });

  testWidgets('closing the dialog hands the view back to the card',
      (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);
    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(_viewKey), findsOneWidget);
    expect(find.text('Playing in the expanded view'), findsNothing);
    expect(playback.plays, 2);
  });

  testWidgets('a paused video stays paused when it moves', (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);
    playback.playing = false;

    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    expect(playback.plays, 0);
  });

  testWidgets('fullscreen from the dialog returns to the dialog',
      (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);
    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect(find.byKey(_viewKey), findsOneWidget);

    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Exit full screen'), findsNothing);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.byKey(_viewKey)),
      findsOneWidget,
    );
  });

  testWidgets('fullscreen from the card returns to the card', (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);

    await tester.tap(find.byTooltip('Full screen'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing);
    expect(find.byKey(_viewKey), findsOneWidget);
    expect(find.text('Playing in the expanded view'), findsNothing);
  });

  testWidgets('a video that cannot play offers to open it instead',
      (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);
    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    reportError!();
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing, reason: 'nothing left to show');
    expect(find.byKey(_viewKey), findsNothing);
    expect(find.text('Open video'), findsOneWidget);
    expect(playback.disposed, isTrue, reason: 'the dead player is released');
  });

  testWidgets('a player that cannot start offers to open the video',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: VideoCard(
            uri: _uri,
            playbackFactory: (_, {required onError}) =>
                Future.error(StateError('no player')),
          ),
        ),
      ),
    );

    await startPlaying(tester);

    expect(find.text('Open video'), findsOneWidget);
  });

  testWidgets('releases the player when the card goes', (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);
    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();

    expect(playback.disposed, isTrue);
    expect(find.byType(Dialog), findsNothing);
  });
}
