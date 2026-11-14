import 'package:better_player/better_player.dart';
import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'video_platform.dart'
    if (dart.library.js_interop) 'video_platform_web.dart';
import 'video_playback.dart';

/// Plays [uri] through `better_player`, starting at once.
///
/// What the configuration settles:
///
/// - The controller outlives its views. `BetterPlayer` disposes its controller
///   when it unmounts unless `autoDispose` is off, and the card unmounts one
///   view each time it hands the video to the dialog or the fullscreen page.
///   [VideoPlayback.dispose] is the only teardown.
/// - better_player draws no controls. The hosts draw `VideoControls` over the
///   view instead. The package's web controls paint a fixed black gradient
///   that ignores the configured colours and stops short of the bottom edge,
///   and they have no slot for the expand and fullscreen actions.
/// - The aspect ratio is the card's 16:9; a video of another shape is
///   letterboxed inside it.
/// - An HLS or DASH stream adapts its rendition to the connection: Shaka's
///   ABR on the web, ExoPlayer's on Android, AVPlayer's on iOS. Its manifest
///   lists the renditions, which become [VideoStatus.qualities].
Future<VideoPlayback> createBetterPlayerPlayback(
  Uri uri, {
  required VoidCallback onError,
}) async {
  await ensureVideoRuntime();
  final controller = BetterPlayerController(
    PlayerConfiguration(
      autoPlay: true,
      autoDispose: false,
      aspectRatio: 16 / 9,
      fit: BoxFit.contain,
      // The card draws its own failure, with a way to open the video instead.
      errorBuilder: (_, __) => const SizedBox.shrink(),
      controlsConfiguration: const PlayerControlsConfiguration(
        showControls: false,
      ),
    ),
    betterPlayerDataSource: PlayerDataSource.network(
      uri.toString(),
      // Passed although the constructor defaults it to true: the `network`
      // factory forwards its own null over that default, and the manifest's
      // renditions are then never listed (better_player 1.37.0).
      useAsmsTracks: true,
    ),
  );
  controller.addEventsListener((event) {
    if (event.betterPlayerEventType == PlayerEventType.exception) onError();
  });
  return _BetterPlayerPlayback(controller);
}

class _BetterPlayerPlayback implements VideoPlayback {
  _BetterPlayerPlayback(this._controller) {
    _controller.addVideoListener(_update);
  }

  final BetterPlayerController _controller;
  final Signal<VideoStatus> _status = signal(const VideoStatus());

  /// The rendition each listed quality stands for.
  final Map<VideoQuality, PlayerAsmsTrack> _tracks = {};
  VideoQuality? _quality;

  @override
  ReadonlySignal<VideoStatus> get status => _status;

  void _update() {
    final value = _controller.videoPlayerValue;
    if (value == null) return;
    _readTracks();
    _status.value = VideoStatus(
      position: value.position,
      duration: value.duration,
      buffered: value.buffered.fold(
        Duration.zero,
        (furthest, range) => range.end > furthest ? range.end : furthest,
      ),
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
      volume: value.volume,
      qualities: List.unmodifiable(_tracks.keys),
      quality: _quality,
    );
  }

  /// Lists the manifest's renditions once it has been read: one per height,
  /// tallest first, leaving out the "auto" entry some manifests parse into.
  void _readTracks() {
    if (_tracks.isNotEmpty) return;
    final byHeight = <int, PlayerAsmsTrack>{};
    for (final track in _controller.betterPlayerAsmsTracks) {
      final height = track.height ?? 0;
      if (height <= 0) continue;
      final kept = byHeight[height];
      if (kept == null || (track.bitrate ?? 0) > (kept.bitrate ?? 0)) {
        byHeight[height] = track;
      }
    }
    final heights = byHeight.keys.toList()..sort((a, b) => b - a);
    // A single rendition is nothing to choose between.
    if (heights.length < 2) return;
    for (final height in heights) {
      _tracks[VideoQuality(label: '${height}p', id: height)] =
          byHeight[height]!;
    }
  }

  @override
  bool get isPlaying => _controller.isPlaying() ?? false;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seekTo(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setVolume(double volume) => _controller.setVolume(volume);

  @override
  void selectQuality(VideoQuality? quality) {
    final track = quality == null ? null : _tracks[quality];
    _controller.setTrack(track ?? PlayerAsmsTrack.defaultTrack());
    _quality = track == null ? null : quality;
    _update();
  }

  @override
  Widget buildView() => BetterPlayer(controller: _controller);

  @override
  void dispose() {
    _controller
      ..removeVideoListener(_update)
      ..dispose(forceDispose: true);
    _status.dispose();
  }
}
