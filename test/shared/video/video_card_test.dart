import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart'
    show soliplexDarkTheme, soliplexLightTheme;
import 'package:soliplex_frontend/src/shared/video/video_card.dart';
import 'package:soliplex_frontend/src/shared/video/video_playback.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

/// Stands in for the platform player: it plays until paused, counts resumes,
/// and, as a browser does to a `<video>` element whose view goes, pauses when
/// a view of it unmounts.
class _FakePlayback implements VideoPlayback {
  int plays = 0;
  bool disposed = false;

  @override
  final Signal<VideoStatus> status = signal(const VideoStatus(isPlaying: true));

  bool get playing => status.value.isPlaying;
  set playing(bool value) => status.value = VideoStatus(isPlaying: value);

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
  Widget buildView() => _FakeView(onUnmount: () => playing = false);

  @override
  void dispose() => disposed = true;
}

class _FakeView extends StatefulWidget {
  const _FakeView({required this.onUnmount}) : super(key: _viewKey);

  final VoidCallback onUnmount;

  @override
  State<_FakeView> createState() => _FakeViewState();
}

class _FakeViewState extends State<_FakeView> {
  @override
  void dispose() {
    // The browser's pause arrives as an event, after the unmount.
    scheduleMicrotask(widget.onUnmount);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

const _viewKey = ValueKey('video-view');
final _uri = Uri.parse('https://cdn.example/clip.mp4');

/// WCAG contrast between two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  late _FakePlayback playback;
  late int created;
  void Function(String reason)? reportError;
  late MemorySink sink;

  setUp(() {
    playback = _FakePlayback();
    created = 0;
    reportError = null;
    sink = MemorySink();
    LogManager.instance.addSink(sink);
  });

  tearDown(LogManager.instance.reset);

  Future<VideoPlayback> factory(
    Uri uri, {
    required void Function(String reason) onError,
  }) async {
    created++;
    reportError = onError;
    return playback;
  }

  Future<void> pumpCard(
    WidgetTester tester, {
    String? caption,
    ThemeData? theme,
    VideoPlaybackFactory? playbackFactory,
  }) =>
      tester.pumpWidget(
        MaterialApp(
          theme: theme ?? soliplexLightTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: VideoCard(
                  uri: _uri,
                  caption: caption,
                  playbackFactory: playbackFactory ?? factory,
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

  testWidgets('a screen reader can press play, named by the caption',
      (tester) async {
    await pumpCard(tester, caption: 'A demo');

    final play = find.bySemanticsLabel('Play A demo');
    expect(
      tester.getSemantics(play),
      matchesSemantics(
        label: 'Play A demo',
        isButton: true,
        hasTapAction: true,
      ),
    );
    tester.semantics.tap(find.semantics.byLabel('Play A demo'));
    await tester.pumpAndSettle();

    expect(created, 1);
  });

  testWidgets('pressing play twice before it starts starts one player',
      (tester) async {
    await pumpCard(tester);

    await tester.tap(find.byTooltip('Play video'));
    await tester.tap(find.byTooltip('Play video'));
    await tester.pumpAndSettle();

    expect(created, 1);
  });

  testWidgets('shows progress while the player starts', (tester) async {
    final starting = Completer<VideoPlayback>();
    await pumpCard(
      tester,
      playbackFactory: (_, {required onError}) => starting.future,
    );

    await tester.tap(find.byTooltip('Play video'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(_viewKey), findsNothing);

    starting.complete(playback);
    await tester.pumpAndSettle();
    expect(find.byKey(_viewKey), findsOneWidget);
  });

  testWidgets('a card that goes while the player starts releases it',
      (tester) async {
    final starting = Completer<VideoPlayback>();
    await pumpCard(
      tester,
      playbackFactory: (_, {required onError}) => starting.future,
    );
    await tester.tap(find.byTooltip('Play video'));
    await tester.pump();

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    starting.complete(playback);
    await tester.pumpAndSettle();

    expect(playback.disposed, isTrue);
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
    expect(playback.playing, isTrue, reason: 'resumed after the move');
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
    expect(playback.playing, isTrue, reason: 'resumed after the move back');
  });

  testWidgets('a paused video stays paused when it moves', (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);
    playback.playing = false;

    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    expect(playback.plays, 0);
    expect(playback.playing, isFalse);
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
    expect(playback.playing, isTrue);

    await tester.tap(find.byTooltip('Exit full screen'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Exit full screen'), findsNothing);
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.byKey(_viewKey)),
      findsOneWidget,
    );
    expect(playback.playing, isTrue);
  });

  testWidgets('a video that cannot play offers to open it instead',
      (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);
    await tester.tap(find.byTooltip('Expand video'));
    await tester.pumpAndSettle();

    reportError!('HTTP 404');
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsNothing, reason: 'nothing left to show');
    expect(find.byKey(_viewKey), findsNothing);
    expect(find.text('Open video'), findsOneWidget);
    expect(playback.disposed, isTrue, reason: 'the dead player is released');
    final record = sink.records.single;
    expect(record.message, 'A video could not be played');
    expect(record.attributes, containsPair('reason', 'HTTP 404'));
    expect(record.attributes, containsPair('host', 'cdn.example'));
  });

  testWidgets('a failure reported twice is handled once', (tester) async {
    await pumpCard(tester);
    await startPlaying(tester);

    reportError!('HTTP 404');
    reportError!('HTTP 404');
    await tester.pumpAndSettle();

    expect(find.text('Open video'), findsOneWidget);
    expect(sink.records, hasLength(1));
  });

  testWidgets('a player that cannot start offers to open the video',
      (tester) async {
    const failure = VideoPlaybackException('HTTP 404');
    await pumpCard(
      tester,
      playbackFactory: (_, {required onError}) => Future.error(failure),
    );

    await startPlaying(tester);

    expect(find.text('Open video'), findsOneWidget);
    final record = sink.records.single;
    expect(record.message, 'Could not start the video player');
    expect(record.error, failure);
  });

  group('rebuilt with another video', () {
    final other = Uri.parse('https://cdn.example/other.mp4');

    Future<void> pumpUri(
      WidgetTester tester,
      Uri uri,
      VideoPlaybackFactory playbackFactory,
    ) =>
        tester.pumpWidget(
          MaterialApp(
            theme: soliplexLightTheme(),
            home: Scaffold(
              body: VideoCard(uri: uri, playbackFactory: playbackFactory),
            ),
          ),
        );

    testWidgets('releases the video it played and offers the other',
        (tester) async {
      await pumpUri(tester, _uri, factory);
      await startPlaying(tester);
      await tester.tap(find.byTooltip('Expand video'));
      await tester.pumpAndSettle();

      await pumpUri(tester, other, factory);
      await tester.pumpAndSettle();

      expect(playback.disposed, isTrue);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byKey(_viewKey), findsNothing);
      expect(find.byTooltip('Play video'), findsOneWidget);
    });

    testWidgets('a start it moved past gives way to the new one',
        (tester) async {
      final starts = <Uri, Completer<VideoPlayback>>{};
      Future<VideoPlayback> slow(
        Uri uri, {
        required void Function(String reason) onError,
      }) =>
          (starts[uri] = Completer<VideoPlayback>()).future;
      final first = _FakePlayback();
      final second = _FakePlayback();
      await pumpUri(tester, _uri, slow);
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();
      await pumpUri(tester, other, slow);
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();

      starts[_uri]!.complete(first);
      await tester.pump();
      await tester.pump();
      expect(first.disposed, isTrue);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      starts[other]!.complete(second);
      await tester.pumpAndSettle();
      expect(find.byKey(_viewKey), findsOneWidget);
      expect(second.disposed, isFalse);
    });

    testWidgets('a start it moved past fails without failing the new one',
        (tester) async {
      final starts = <Uri, Completer<VideoPlayback>>{};
      Future<VideoPlayback> slow(
        Uri uri, {
        required void Function(String reason) onError,
      }) =>
          (starts[uri] = Completer<VideoPlayback>()).future;
      await pumpUri(tester, _uri, slow);
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();
      await pumpUri(tester, other, slow);
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();

      starts[_uri]!.completeError(const VideoPlaybackException('HTTP 404'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Open video'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      starts[other]!.complete(playback);
      await tester.pumpAndSettle();
      expect(find.byKey(_viewKey), findsOneWidget);
    });

    testWidgets('releases the video still starting', (tester) async {
      final starting = Completer<VideoPlayback>();
      Future<VideoPlayback> slow(
        Uri uri, {
        required void Function(String reason) onError,
      }) =>
          starting.future;
      await pumpUri(tester, _uri, slow);
      await tester.tap(find.byTooltip('Play video'));
      await tester.pump();

      await pumpUri(tester, other, slow);
      starting.complete(playback);
      await tester.pumpAndSettle();

      expect(playback.disposed, isTrue);
      expect(find.byKey(_viewKey), findsNothing);
      expect(find.byTooltip('Play video'), findsOneWidget);
    });
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

  group('in the dark theme', () {
    Future<Color> textColour(WidgetTester tester, String text) async =>
        tester.widget<Text>(find.text(text)).style!.color!;

    testWidgets('the failure reads against the black card', (tester) async {
      final theme = soliplexDarkTheme();
      await pumpCard(
        tester,
        theme: theme,
        playbackFactory: (_, {required onError}) =>
            Future.error(const VideoPlaybackException('HTTP 404')),
      );
      await startPlaying(tester);

      final colour =
          await textColour(tester, "This video can't be played here.");
      expect(_contrast(colour, theme.colorScheme.scrim), greaterThan(4.5));
    });

    testWidgets('"playing elsewhere" reads against the black card',
        (tester) async {
      final theme = soliplexDarkTheme();
      await pumpCard(tester, theme: theme);
      await startPlaying(tester);
      await tester.tap(find.byTooltip('Expand video'));
      await tester.pumpAndSettle();

      final colour = await textColour(tester, 'Playing in the expanded view');
      expect(_contrast(colour, theme.colorScheme.scrim), greaterThan(4.5));
    });
  });
}
