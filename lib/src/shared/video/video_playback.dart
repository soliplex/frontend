import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// One rendition of a streamed video the viewer can pin playback to.
@immutable
class VideoQuality {
  const VideoQuality({required this.label, required this.id});

  /// What the quality menu shows, such as `720p`.
  final String label;

  /// Identifies the rendition to the playback that listed it.
  final Object id;

  @override
  bool operator ==(Object other) =>
      other is VideoQuality && other.label == label && other.id == id;

  @override
  int get hashCode => Object.hash(label, id);
}

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

  /// Null until the player knows it, and for a live stream.
  final Duration? duration;

  /// How far ahead of the start the player has loaded.
  final Duration buffered;

  final bool isPlaying;

  /// Waiting for data: the controls show a spinner.
  final bool isBuffering;

  /// From 0 (muted) to 1.
  final double volume;

  /// The renditions an adaptive stream (HLS or DASH) offers, best first.
  /// Empty for a plain video file, which has only the one.
  final List<VideoQuality> qualities;

  /// The rendition playback is pinned to, or null when the player picks one
  /// to suit the connection, which is the default.
  final VideoQuality? quality;
}

/// One video's playback, which the inline card, its dialog and its fullscreen
/// page take turns showing.
///
/// The seam the video widgets are written against, so they can be tested
/// without a platform player; [createBetterPlayerPlayback] is the real one.
abstract interface class VideoPlayback {
  /// Where playback stands, updated as it plays.
  ReadonlySignal<VideoStatus> get status;

  /// Whether the video is playing now.
  bool get isPlaying;

  /// Starts or resumes playback.
  Future<void> play();

  Future<void> pause();

  Future<void> seekTo(Duration position);

  /// Sets the volume, from 0 (muted) to 1.
  Future<void> setVolume(double volume);

  /// Pins playback to [quality], one of [VideoStatus.qualities], or, when
  /// null, lets the player adapt it to the connection again.
  void selectQuality(VideoQuality? quality);

  /// A view of the video alone; the hosts draw the controls over it.
  ///
  /// At most one may be mounted at a time. On the web every view of one
  /// playback shows the same `<video>` element, which the newest view takes
  /// from the others.
  Widget buildView();

  /// Stops playback and releases the player. Called once, by the owner.
  void dispose();
}

/// Creates the playback of the video at [uri] and starts it.
///
/// [onError] is called when the video cannot be played: the source failed to
/// load, or the format is unsupported.
typedef VideoPlaybackFactory = Future<VideoPlayback> Function(
  Uri uri, {
  required VoidCallback onError,
});
