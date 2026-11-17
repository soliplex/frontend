import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

/// How long a video, or on the web the player itself, may take to load
/// before it counts as unplayable.
///
/// A dead source is reported by the player itself; this catches what
/// reports nothing: a platform player whose setup failed, which better_player
/// starts without waiting on, or a request the server never finishes.
const videoStartLimit = Duration(seconds: 30);

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
///
/// Its commands never throw: one the player refuses is logged and leaves the
/// video as it was, so the widgets fire them without awaiting.
abstract interface class VideoPlayback {
  /// Where playback stands, updated as it plays.
  ReadonlySignal<VideoStatus> get status;

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

/// Creates the playback of the video at [uri] and asks it to play,
/// completing once the video has loaded. A browser may still refuse to play
/// it unprompted, leaving it paused.
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
/// [reason] says why: the player's own account of the failure, or that the
/// video did not load in time. Nothing in it can hold a credential: each URL
/// in it keeps only its scheme, host, port and path, and a Shaka error only
/// its codes and HTTP status.
class VideoPlaybackException implements Exception {
  const VideoPlaybackException(this.reason);

  final String reason;

  @override
  String toString() => 'VideoPlaybackException: $reason';
}
