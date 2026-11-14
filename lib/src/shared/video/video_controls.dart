import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'video_playback.dart';

/// What the controls of one host can do besides playback: the moves between
/// hosts. A null action leaves its button out.
@immutable
class VideoHostActions {
  const VideoHostActions({
    this.expand,
    this.enterFullscreen,
    this.exitFullscreen,
  });

  final VoidCallback? expand;
  final VoidCallback? enterFullscreen;
  final VoidCallback? exitFullscreen;
}

/// The controls drawn over a video: a rail along the bottom with the
/// progress bar, play, mute, time, quality and the [actions], shown while
/// the pointer moves over the video and for a few seconds after, and always
/// while the video is paused.
///
/// The rail sits on a scrim that darkens to its bottom edge and draws its
/// icons in a light colour, in either theme: a video can be any colour, so
/// the scrim, not the page, is the background the icons must stand out from.
class VideoControls extends StatefulWidget {
  const VideoControls({
    required this.playback,
    this.actions = const VideoHostActions(),
    super.key,
  });

  final VideoPlayback playback;
  final VideoHostActions actions;

  /// How long the rail stays after the pointer stops, while the video plays.
  static const hideAfter = Duration(seconds: 3);

  @override
  State<VideoControls> createState() => _VideoControlsState();
}

class _VideoControlsState extends State<VideoControls> {
  bool _shown = true;
  Timer? _hideTimer;
  bool _menuOpen = false;

  /// The position the progress bar is being dragged to, while it is.
  double? _scrubMs;

  /// The volume to restore on unmute.
  double _volumeBeforeMute = 1;

  VideoPlayback get _playback => widget.playback;

  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _reveal() {
    if (!_shown) setState(() => _shown = true);
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(VideoControls.hideAfter, () {
      if (!mounted || _menuOpen || _scrubMs != null) return;
      setState(() => _shown = false);
    });
  }

  void _togglePlay() {
    unawaited(_playback.isPlaying ? _playback.pause() : _playback.play());
    _reveal();
  }

  void _toggleMute(VideoStatus status) {
    if (status.volume > 0) {
      _volumeBeforeMute = status.volume;
      unawaited(_playback.setVolume(0));
    } else {
      unawaited(_playback.setVolume(_volumeBeforeMute));
    }
    _reveal();
  }

  /// A mouse click plays or pauses, as on any web player. A touch shows the
  /// controls when they are hidden and hides them when they are not, so a
  /// finger aimed at the rail never stops the video by missing.
  void _onTapVideo(PointerDeviceKind kind) {
    if (kind == PointerDeviceKind.mouse) {
      _togglePlay();
    } else if (_shown) {
      _hideTimer?.cancel();
      setState(() => _shown = false);
    } else {
      _reveal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = _OverlayPalette.of(Theme.of(context).colorScheme);
    return Watch((context) {
      final status = _playback.status.value;
      final visible = _shown || !status.isPlaying;
      // Its own Material: the fullscreen page has none above it.
      return Material(
        type: MaterialType.transparency,
        child: MouseRegion(
          onHover: (_) => _reveal(),
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTapVideo(details.kind),
              ),
              if (status.isBuffering)
                Center(child: CircularProgressIndicator(color: palette.accent)),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: IgnorePointer(
                  ignoring: !visible,
                  child: AnimatedOpacity(
                    opacity: visible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: _rail(context, status, palette),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _rail(
    BuildContext context,
    VideoStatus status,
    _OverlayPalette palette,
  ) {
    final actions = widget.actions;
    final muted = status.volume == 0;
    IconButton button({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) =>
        IconButton(
          icon: Icon(icon),
          tooltip: tooltip,
          color: palette.foreground,
          visualDensity: VisualDensity.compact,
          onPressed: onPressed,
        );

    return DecoratedBox(
      decoration: BoxDecoration(
        // Clear at the top, so the rail fades into the picture, and darkest
        // at the bottom edge, which it reaches.
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            palette.scrim.withValues(alpha: 0),
            palette.scrim.withValues(alpha: 0.75),
            palette.scrim.withValues(alpha: 0.9),
          ],
          stops: const [0, 0.45, 1],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SoliplexSpacing.s2,
          SoliplexSpacing.s6,
          SoliplexSpacing.s2,
          SoliplexSpacing.s1,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _progressBar(status, palette),
            Row(
              children: [
                button(
                  icon: status.isPlaying ? Icons.pause : Icons.play_arrow,
                  tooltip: status.isPlaying ? 'Pause' : 'Play',
                  onPressed: _togglePlay,
                ),
                button(
                  icon: muted ? Icons.volume_off : Icons.volume_up,
                  tooltip: muted ? 'Unmute' : 'Mute',
                  onPressed: () => _toggleMute(status),
                ),
                const SizedBox(width: SoliplexSpacing.s1),
                Expanded(
                  child: Text(
                    _timeLabel(status),
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: palette.foreground,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                if (status.qualities.isNotEmpty) _qualityMenu(status, palette),
                if (actions.expand case final expand?)
                  button(
                    icon: Icons.open_in_full,
                    tooltip: 'Expand video',
                    onPressed: expand,
                  ),
                if (actions.enterFullscreen case final enter?)
                  button(
                    icon: Icons.fullscreen,
                    tooltip: 'Full screen',
                    onPressed: enter,
                  ),
                if (actions.exitFullscreen case final exit?)
                  button(
                    icon: Icons.fullscreen_exit,
                    tooltip: 'Exit full screen',
                    onPressed: exit,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _progressBar(VideoStatus status, _OverlayPalette palette) {
    final totalMs = status.duration?.inMilliseconds.toDouble() ?? 0;
    final known = totalMs > 0;
    double clamp(double ms) => known ? ms.clamp(0, totalMs) : 0;
    return SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        padding: const EdgeInsets.symmetric(horizontal: SoliplexSpacing.s3),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
        activeTrackColor: palette.accent,
        thumbColor: palette.accent,
        secondaryActiveTrackColor: palette.foreground.withValues(alpha: 0.55),
        inactiveTrackColor: palette.foreground.withValues(alpha: 0.3),
        disabledActiveTrackColor: palette.foreground.withValues(alpha: 0.3),
        disabledInactiveTrackColor: palette.foreground.withValues(alpha: 0.3),
        overlayColor: palette.accent.withValues(alpha: 0.2),
      ),
      child: SizedBox(
        height: SoliplexSpacing.s6,
        child: Slider(
          semanticFormatterCallback: (ms) =>
              _format(Duration(milliseconds: ms.round())),
          value: clamp(_scrubMs ?? status.position.inMilliseconds.toDouble()),
          secondaryTrackValue: clamp(status.buffered.inMilliseconds.toDouble()),
          max: known ? totalMs : 1,
          onChangeStart: known
              ? (ms) {
                  _hideTimer?.cancel();
                  setState(() => _scrubMs = ms);
                }
              : null,
          onChanged: known ? (ms) => setState(() => _scrubMs = ms) : null,
          onChangeEnd: known
              ? (ms) {
                  unawaited(
                    _playback.seekTo(Duration(milliseconds: ms.round())),
                  );
                  setState(() => _scrubMs = null);
                  _scheduleHide();
                }
              : null,
        ),
      ),
    );
  }

  Widget _qualityMenu(VideoStatus status, _OverlayPalette palette) {
    const auto = -1;
    final current = status.quality == null
        ? auto
        : status.qualities.indexOf(status.quality!);
    return PopupMenuButton<int>(
      icon: const Icon(Icons.high_quality_outlined),
      iconColor: palette.foreground,
      tooltip: 'Quality',
      style: const ButtonStyle(visualDensity: VisualDensity.compact),
      onOpened: () {
        _hideTimer?.cancel();
        _menuOpen = true;
      },
      onCanceled: () {
        _menuOpen = false;
        _scheduleHide();
      },
      onSelected: (index) {
        _menuOpen = false;
        _playback.selectQuality(index == auto ? null : status.qualities[index]);
        _scheduleHide();
      },
      itemBuilder: (_) => [
        CheckedPopupMenuItem(
          value: auto,
          checked: current == auto,
          child: const Text('Auto'),
        ),
        for (final (index, quality) in status.qualities.indexed)
          CheckedPopupMenuItem(
            value: index,
            checked: current == index,
            child: Text(quality.label),
          ),
      ],
    );
  }

  String _timeLabel(VideoStatus status) {
    final position = _scrubMs == null
        ? status.position
        : Duration(milliseconds: _scrubMs!.round());
    final duration = status.duration;
    return duration == null || duration == Duration.zero
        ? _format(position)
        : '${_format(position)} / ${_format(duration)}';
  }
}

String _format(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  final minutes = d.inMinutes.remainder(60);
  final seconds = two(d.inSeconds.remainder(60));
  return d.inHours > 0
      ? '${d.inHours}:${two(minutes)}:$seconds'
      : '$minutes:$seconds';
}

/// A dark scrim with light content, whichever the theme: a light theme's
/// inverse colours, a dark theme's own.
class _OverlayPalette {
  const _OverlayPalette({
    required this.scrim,
    required this.foreground,
    required this.accent,
  });

  factory _OverlayPalette.of(ColorScheme colors) {
    final dark = colors.brightness == Brightness.dark;
    return _OverlayPalette(
      scrim: colors.scrim,
      foreground: dark ? colors.onSurface : colors.onInverseSurface,
      accent: dark ? colors.primary : colors.inversePrimary,
    );
  }

  final Color scrim;
  final Color foreground;
  final Color accent;
}
