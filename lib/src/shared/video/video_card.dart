import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../markdown/launch_markdown_link.dart';
import '../zoomable_view.dart';
import 'better_player_playback.dart';
import 'video_controls.dart';
import 'video_handoff.dart';
import 'video_platform.dart'
    if (dart.library.js_interop) 'video_platform_web.dart';
import 'video_playback.dart';

final _logger = LogManager.instance.getLogger('soliplex_frontend.video');

/// A message-wide, 16:9 player for the video at [uri], which can be expanded
/// into a dialog and from either into a fullscreen page.
///
/// Nothing is loaded until the user presses play, so a conversation holding
/// many videos starts no players of its own accord. The card owns the
/// playback from then on, and the dialog and the fullscreen page borrow its
/// view through a [VideoHandoff], so the video keeps playing, from where it
/// was, wherever it is shown.
///
/// A video that cannot be played — a dead link, an unsupported format, or on
/// the web an HLS stream from a host that does not allow cross-origin requests
/// (a plain video file needs no such permission) — offers to open [uri] in the
/// browser instead.
class VideoCard extends StatefulWidget {
  const VideoCard({
    required this.uri,
    this.caption,
    this.playbackFactory = createBetterPlayerPlayback,
    super.key,
  });

  final Uri uri;

  /// Shown beneath the card; the markdown image's alt text.
  final String? caption;

  /// Creates the playback. Tests pass a fake.
  final VideoPlaybackFactory playbackFactory;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

/// Where the card's video stands. Only a playing card has a handoff.
sealed class _CardState {
  const _CardState();
}

class _Idle extends _CardState {
  const _Idle();
}

/// Not const: each start is its own instance, so a start the card has since
/// moved past can tell.
class _Starting extends _CardState {
  _Starting();
}

class _Playing extends _CardState {
  const _Playing(this.handoff);

  final VideoHandoff handoff;
}

class _Unplayable extends _CardState {
  const _Unplayable();
}

class _VideoCardState extends State<VideoCard> {
  _CardState _state = const _Idle();

  /// The dialog and fullscreen routes open on this card's video, closed
  /// should the card fail or go first, since their views would outlive the
  /// playback.
  final Set<Route<Object?>> _openRoutes = {};
  bool _inFullscreen = false;

  @override
  void dispose() {
    _closeOpenRoutes();
    if (_state case _Playing(:final handoff)) handoff.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.uri == oldWidget.uri) return;
    _release();
    _state = const _Idle();
  }

  Future<void> _start() async {
    if (_state is! _Idle) return;
    final starting = _Starting();
    setState(() => _state = starting);
    final uri = widget.uri;
    final VideoPlayback playback;
    try {
      playback = await widget.playbackFactory(uri, onError: _fail);
    } on Object catch (error, stackTrace) {
      // A VideoPlaybackException, whose reason holds nothing that could be a
      // credential (see VideoPlaybackException.reason).
      _logger.warning(
        'Could not start the video player',
        error: error,
        stackTrace: stackTrace,
        attributes: _sourceAttributes(uri),
      );
      if (mounted && identical(_state, starting)) {
        setState(() => _state = const _Unplayable());
      }
      return;
    }
    final handoff = VideoHandoff(playback);
    if (!mounted || !identical(_state, starting)) {
      handoff.dispose();
      return;
    }
    setState(() => _state = _Playing(handoff));
  }

  /// [reason] holds nothing that could be a credential (see
  /// [VideoPlaybackException.reason]).
  void _fail(String reason) {
    if (!mounted || _state is! _Playing) return;
    _logger.warning(
      'A video could not be played',
      attributes: {..._sourceAttributes(widget.uri), 'reason': reason},
    );
    _release();
    setState(() => _state = const _Unplayable());
  }

  /// Closes the routes showing the video and releases it once its view is
  /// gone, outside the player's own event dispatch, which [_fail] is called
  /// from.
  void _release() {
    _closeOpenRoutes();
    if (_state case _Playing(:final handoff)) {
      WidgetsBinding.instance.addPostFrameCallback((_) => handoff.dispose());
    }
  }

  /// Removes the routes open on this card's video. Removing a route runs no
  /// `PopScope`, so the fullscreen page's own restoring is repeated here.
  void _closeOpenRoutes() {
    for (final route in List.of(_openRoutes)) {
      if (route.isActive) route.navigator?.removeRoute(route);
    }
    _openRoutes.clear();
    if (_inFullscreen) _leaveFullscreenChrome();
  }

  void _leaveFullscreenChrome() {
    _inFullscreen = false;
    exitBrowserFullscreen();
    if (!kIsWeb) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
  }

  void _expand(VideoHandoff handoff) {
    unawaited(showZoomableMediaDialog(
      context,
      viewer: _RouteRegistration(
        routes: _openRoutes,
        child: PopScope(
          onPopInvokedWithResult: (_, __) {
            unawaited(handoff.moveTo(VideoHost.inline));
          },
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: VideoHostView(
                handoff: handoff,
                host: VideoHost.dialog,
                actions: VideoHostActions(
                  enterFullscreen: () =>
                      _openFullscreen(handoff, VideoHost.dialog),
                ),
              ),
            ),
          ),
        ),
      ),
      caption: _captionFor(context),
    ));
    unawaited(handoff.moveTo(VideoHost.dialog));
  }

  void _openFullscreen(VideoHandoff handoff, VideoHost returnTo) {
    final navigator = Navigator.of(context, rootNavigator: true);
    // Inside the tap: a page may only go fullscreen during a user gesture.
    // Leaving it from the browser (Escape) closes the page too.
    enterBrowserFullscreen(onExit: navigator.maybePop);
    if (!kIsWeb) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersive));
    }
    _inFullscreen = true;
    final route = PageRouteBuilder<void>(
      pageBuilder: (context, _, __) => _FullscreenPage(
        handoff: handoff,
        onLeave: () {
          unawaited(handoff.moveTo(returnTo));
          _leaveFullscreenChrome();
        },
      ),
    );
    _openRoutes.add(route);
    unawaited(
        navigator.push(route).whenComplete(() => _openRoutes.remove(route)));
    unawaited(handoff.moveTo(VideoHost.fullscreen));
  }

  Widget? _captionFor(BuildContext context) {
    final caption = widget.caption;
    if (caption == null || caption.isEmpty) return null;
    return Padding(
      padding: const EdgeInsets.all(SoliplexSpacing.s2),
      child: Text(
        caption,
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final caption = _captionFor(context);
    return SizedBox(
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(context.radii.md),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: colors.scrim,
                child: switch (_state) {
                  _Idle() => _Poster(
                      label: widget.caption,
                      onPlay: _start,
                    ),
                  _Starting() => const Center(
                      child: CircularProgressIndicator(),
                    ),
                  _Unplayable() => _Failed(uri: widget.uri),
                  _Playing(:final handoff) => VideoHostView(
                      handoff: handoff,
                      host: VideoHost.inline,
                      actions: VideoHostActions(
                        expand: () => _expand(handoff),
                        enterFullscreen: () =>
                            _openFullscreen(handoff, VideoHost.inline),
                      ),
                      placeholder: const _ShownElsewhere(),
                    ),
                },
              ),
            ),
          ),
          if (caption != null) caption,
        ],
      ),
    );
  }
}

Map<String, Object> _sourceAttributes(Uri uri) => {
      // Not the query: a signed media URL carries its credential there.
      'host': uri.host,
      'path': uri.path,
      'queryLength': uri.query.length,
    };

class _Poster extends StatelessWidget {
  const _Poster({required this.label, required this.onPlay});

  final String? label;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final label = this.label;
    return Semantics(
      button: true,
      label: label == null || label.isEmpty ? 'Play video' : 'Play $label',
      excludeSemantics: true,
      child: InkWell(
        onTap: onPlay,
        child: Center(
          child: IconButton.filledTonal(
            onPressed: onPlay,
            iconSize: SoliplexSpacing.s6 * 2,
            icon: const Icon(Icons.play_arrow),
            tooltip: 'Play video',
          ),
        ),
      ),
    );
  }
}

class _ShownElsewhere extends StatelessWidget {
  const _ShownElsewhere();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Text(
        'Playing in the expanded view',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: colors.onInverseSurface),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  const _Failed({required this.uri});

  final Uri uri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(SoliplexSpacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              "This video can't be played here.",
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: colors.onInverseSurface),
            ),
            const SizedBox(height: SoliplexSpacing.s2),
            SoliplexButton.filled(
              onPressed: () => launchMarkdownLink(uri.toString()),
              icon: const Icon(Icons.open_in_new),
              child: const Text('Open video'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Adds the route [child] is shown in to [routes] for as long as it is.
class _RouteRegistration extends StatefulWidget {
  const _RouteRegistration({required this.routes, required this.child});

  final Set<Route<Object?>> routes;
  final Widget child;

  @override
  State<_RouteRegistration> createState() => _RouteRegistrationState();
}

class _RouteRegistrationState extends State<_RouteRegistration> {
  Route<Object?>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == _route) return;
    if (_route != null) widget.routes.remove(_route);
    _route = route;
    if (route != null) widget.routes.add(route);
  }

  @override
  void dispose() {
    widget.routes.remove(_route);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _FullscreenPage extends StatelessWidget {
  const _FullscreenPage({required this.handoff, required this.onLeave});

  final VideoHandoff handoff;

  /// Hands the view back and restores the screen, as the page starts to close.
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PopScope(
      onPopInvokedWithResult: (_, __) => onLeave(),
      child: ColoredBox(
        color: colors.scrim,
        child: SafeArea(
          child: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: VideoHostView(
                handoff: handoff,
                host: VideoHost.fullscreen,
                actions: VideoHostActions(
                  exitFullscreen: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
