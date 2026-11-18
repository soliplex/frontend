import 'dart:async';

import 'package:better_player/better_player.dart';
import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import 'video_platform.dart'
    if (dart.library.js_interop) 'video_platform_web.dart';
import 'video_playback.dart';
import 'video_uri.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.video');

/// Plays [uri] through `better_player`, completing once the video has loaded.
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
/// - An HLS stream adapts its rendition to the connection: Shaka's ABR on the
///   web, ExoPlayer's on Android, AVPlayer's on iOS and macOS, libmpv's on
///   Windows and Linux. The renditions its manifest lists become
///   [VideoStatus.qualities], as [qualitiesFrom] picks them.
/// - better_player logs nothing: its log prints the source URL whole, query
///   included.
Future<VideoPlayback> createBetterPlayerPlayback(
  Uri uri, {
  required void Function(String reason) onError,
}) async {
  await ensureVideoRuntime();
  final controller = BetterPlayerController(
    PlayerConfiguration(
      autoPlay: true,
      autoDispose: false,
      aspectRatio: videoAspectRatio,
      fit: BoxFit.contain,
      // The card draws its own failure, with a way to open the video instead.
      errorBuilder: (_, __) => const SizedBox.shrink(),
      controlsConfiguration: const PlayerControlsConfiguration(
        showControls: false,
      ),
      playerLogConfiguration: const PlayerLoggerConfiguration(
        logLevel: PlayerLogLevel.none,
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
  final loaded = Completer<void>();
  // A failure fails the start until the video has loaded, and is reported
  // through [onError] from then on.
  void Function(String reason) fail = (reason) {
    if (!loaded.isCompleted) {
      loaded.completeError(VideoPlaybackException(reason));
    }
  };
  controller.addEventsListener((event) {
    final type = event.betterPlayerEventType;
    if (type == PlayerEventType.initialized && !loaded.isCompleted) {
      loaded.complete();
    } else if (type == PlayerEventType.exception) {
      fail(withoutCredentials('${event.parameters?['exception']}'));
    }
  });
  try {
    await loaded.future.timeout(
      videoStartLimit,
      onTimeout: () => throw VideoPlaybackException(
        'the video did not load within ${videoStartLimit.inSeconds} seconds',
      ),
    );
  } on VideoPlaybackException {
    controller.dispose(forceDispose: true);
    rethrow;
  }
  fail = onError;
  return _BetterPlayerPlayback(controller, uri);
}

/// [text], a player's account of a failure, without what could hold a
/// credential: each URL keeps its scheme, host, port and path, and a Shaka
/// error keeps its severity, category, code and HTTP status but not the
/// response body and headers it carries.
String withoutCredentials(String text) =>
    _withShakaErrorsReduced(text).replaceAllMapped(_url, (match) {
      final uri = Uri.tryParse(match[0]!);
      if (uri == null) return '<url>';
      final port = uri.hasPort ? ':${uri.port}' : '';
      return '${uri.scheme}://${uri.host}$port${uri.path}';
    });

final _url = RegExp(r'''[a-zA-Z][a-zA-Z0-9+.-]*://[^\s"'<>,)]+''');

/// better_player_web reports a failed load as the whole `shaka.util.Error`
/// in JSON, which nothing follows but the exception's closing fields, so the
/// match runs to its last brace.
final _shakaError = RegExp(r'shaka\.util\.Error \{.*\}', dotAll: true);

String _withShakaErrorsReduced(String text) =>
    text.replaceAllMapped(_shakaError, (match) {
      final json = match[0]!;
      String? field(String name) =>
          RegExp('"$name": (\\d+)').firstMatch(json)?.group(1);
      final code = field('code');
      // For 1001 (BAD_HTTP_STATUS) the status follows the URL in `data`.
      final status = code == '1001'
          ? RegExp(r'"data": \[\s*"(?:[^"\\]|\\.)*",\s*(\d+)')
              .firstMatch(json)
              ?.group(1)
          : null;
      return 'shaka.util.Error severity ${field('severity')}, '
          'category ${field('category')}, code $code'
          '${status == null ? '' : ', HTTP $status'}';
    });

/// The renditions of [tracks] worth offering, each with the track it plays:
/// one per height, at that height's highest bitrate, tallest first. Tracks
/// without a height, such as the "auto" entry some manifests parse into, are
/// left out, and a single height is nothing to choose between, so gives none.
Map<int, PlayerAsmsTrack> qualitiesFrom(
  Iterable<PlayerAsmsTrack> tracks,
) {
  final byHeight = <int, PlayerAsmsTrack>{};
  for (final track in tracks) {
    final height = track.height ?? 0;
    if (height <= 0) continue;
    final kept = byHeight[height];
    if (kept == null || (track.bitrate ?? 0) > (kept.bitrate ?? 0)) {
      byHeight[height] = track;
    }
  }
  if (byHeight.length < 2) return const {};
  final heights = byHeight.keys.toList()..sort((a, b) => b - a);
  return {for (final height in heights) height: byHeight[height]!};
}

class _BetterPlayerPlayback implements VideoPlayback {
  _BetterPlayerPlayback(this._controller, this._uri) {
    _controller
      ..addVideoListener(_update)
      // A finished video reads as paused, but the native players still mean
      // to play: Android's resumes on the next seek, behind a Play button.
      ..addEventsListener((event) {
        if (event.betterPlayerEventType == PlayerEventType.finished) {
          unawaited(pause());
        }
      });
    // The video has loaded by now; the status starts from where it stands.
    _update();
  }

  final BetterPlayerController _controller;
  final Uri _uri;
  final Signal<VideoStatus> _status = signal(const VideoStatus());

  /// The rendition each listed quality stands for.
  final Map<int, PlayerAsmsTrack> _tracks = {};
  int? _quality;

  @override
  ReadonlySignal<VideoStatus> get status => _status;

  void _update() {
    final value = _controller.videoPlayerValue;
    if (value == null) return;
    if (_tracks.isEmpty) {
      _tracks.addAll(qualitiesFrom(_controller.betterPlayerAsmsTracks));
    }
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

  /// Plays on, or from the beginning once the video has ended: the native
  /// players only resume, and stay at the end.
  @override
  Future<void> play() => _run('play', () async {
        final status = _status.value;
        final duration = status.duration;
        if (duration != null &&
            duration > Duration.zero &&
            status.position >= duration) {
          await _controller.seekTo(Duration.zero);
        }
        await _controller.play();
      });

  @override
  Future<void> pause() => _run('pause', _controller.pause);

  @override
  Future<void> seekTo(Duration position) =>
      _run('seekTo', () => _controller.seekTo(position));

  @override
  Future<void> setVolume(double volume) =>
      _run('setVolume', () => _controller.setVolume(volume));

  /// Runs [command], logging a failure rather than throwing it: the callers
  /// fire commands from taps and moves, and a refused command leaves the
  /// video as it was.
  Future<void> _run(String operation, Future<void> Function() command) async {
    try {
      await command();
    } on Object catch (error, stackTrace) {
      _logger.warning(
        'A video command failed',
        stackTrace: stackTrace,
        attributes: {
          ...videoSourceAttributes(_uri),
          'operation': operation,
          // A platform's error text can name the source.
          'failure': withoutCredentials('$error'),
        },
      );
    }
  }

  @override
  void selectQuality(int? height) {
    final track = _tracks[height];
    _controller.setTrack(track ?? PlayerAsmsTrack.defaultTrack());
    _quality = track == null ? null : height;
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
