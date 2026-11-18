import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// How long a video, or on the web the player itself, may take to load
/// before it counts as unplayable.
///
/// A dead source is reported by the player itself; this catches what
/// reports nothing: a platform player that never reports the video loaded,
/// or a request the server never finishes.
const videoStartLimit = Duration(seconds: 30);

/// The shape of every place a video is shown; a video of another shape is
/// letterboxed inside it.
const videoAspectRatio = 16 / 9;

/// Where a playback stands, as its controls draw it.
@immutable
class VideoStatus {
  const VideoStatus({
    this.position = Duration.zero,
    this.duration,
    this.buffered = Duration.zero,
    this.isPlaying = false,
    this.isBuffering = false,
    this.volume = 1,
    this.qualities = const [],
    this.quality,
  });

  final Duration position;

  /// Null or zero while the player does not know it, as for a live stream.
  final Duration? duration;

  /// The end of the furthest range the player has loaded.
  final Duration buffered;

  final bool isPlaying;

  /// Waiting for data: the controls show a spinner.
  final bool isBuffering;

  /// From 0 (muted) to 1.
  final double volume;

  /// The renditions an HLS stream offers, as heights in pixels, tallest
  /// first. Empty when there is nothing to choose between: a plain video
  /// file, or a stream whose renditions are all one height.
  final List<int> qualities;

  /// The height chosen in [VideoPlayback.selectQuality], or null for the
  /// player's own choice, which is the default.
  final int? quality;
}

/// One video's playback, which the inline card, its dialog and its fullscreen
/// page take turns showing.
///
/// The seam the video widgets are written against, so they can be tested
/// without a platform player; `createBetterPlayerPlayback` is the real one.
///
/// Its play, pause, seek and volume commands never throw: one the player
/// refuses is logged, so the widgets fire them without awaiting.
abstract interface class VideoPlayback {
  /// Where playback stands, updated as it plays.
  ReadonlySignal<VideoStatus> get status;

  /// Starts or resumes playback.
  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  /// Sets the volume, from 0 (muted) to 1.
  Future<void> setVolume(double volume);

  /// Keeps playback to the rendition [height] tall, one of
  /// [VideoStatus.qualities], or, when null, returns to the player's own
  /// choice. The web, Windows and Linux play that rendition; Android, iOS and
  /// macOS cap resolution and bitrate at it.
  void selectQuality(int? height);

  /// A view of the video alone; the hosts draw the controls over it.
  ///
  /// At most one may be mounted at a time: on the web every view of one
  /// playback shows the same `<video>` element, which a second view would take
  /// from the first.
  Widget buildView();

  /// Stops playback and releases the player. Called once, by the owner.
  void dispose();
}

/// Creates the playback of the video at [uri] and asks it to play,
/// completing once the video has loaded. A browser may still refuse to play
/// it unprompted; better_player_web does not report a refusal, so the status
/// would then show it playing over a paused video.
///
/// Throws [VideoPlaybackException] when it cannot load: the source failed, the
/// format is unsupported, the web player's script could not be loaded, or
/// nothing arrived within [videoStartLimit]. [onError] is called, only after
/// the returned future completes, when playback fails later.
typedef VideoPlaybackFactory = Future<VideoPlayback> Function(
  Uri uri, {
  required void Function(String reason) onError,
});

/// Why a video could not be played.
///
/// [reason] says why: the player's own account of the failure, passed
/// through `withoutCredentials`, or fixed text naming what did not load in
/// time or at all (the video, or on the web the player's script, by path).
class VideoPlaybackException implements Exception {
  const VideoPlaybackException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoPlaybackException: $reason';
}
