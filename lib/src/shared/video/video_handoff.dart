import 'package:flutter/widgets.dart';
import 'package:signals_flutter/signals_flutter.dart';

import 'video_controls.dart';
import 'video_playback.dart';

/// The places one video can be shown.
enum VideoHost { inline, dialog, fullscreen }

/// Which host shows a video's view, and the moves between them.
///
/// Exactly one host shows the view; the others show a placeholder. On the web
/// every view of a playback shows the same `<video>` element, so two mounted
/// views would fight over it, and the browser pauses a media element whenever
/// it is moved. [moveTo] reads whether the video was playing before the move
/// and resumes it once the new view has taken the element.
class VideoHandoff {
  VideoHandoff(this.playback);

  final VideoPlayback playback;

  /// The host showing the view.
  final Signal<VideoHost> owner = signal(VideoHost.inline);

  /// Shows the view in [host] instead, keeping playback going.
  ///
  /// Call it before the outgoing host's route is torn down — from the route's
  /// `PopScope` when it is the one closing — because tearing it down is what
  /// pauses the video, and the state is read first.
  Future<void> moveTo(VideoHost host) async {
    if (owner.value == host) return;
    final wasPlaying = playback.isPlaying;
    owner.value = host;
    if (!wasPlaying) return;
    // One frame for the new view to mount, one for it to take the element.
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await playback.play();
  }

  void dispose() => owner.dispose();
}

/// Shows the handoff's view, with its controls, when [host] owns it, and
/// [placeholder] otherwise.
class VideoHostView extends StatelessWidget {
  const VideoHostView({
    required this.handoff,
    required this.host,
    this.actions = const VideoHostActions(),
    this.placeholder = const SizedBox.expand(),
    super.key,
  });

  final VideoHandoff handoff;
  final VideoHost host;

  /// The moves to other hosts this host's controls offer.
  final VideoHostActions actions;
  final Widget placeholder;

  @override
  Widget build(BuildContext context) => Watch(
        (context) => handoff.owner.value == host
            ? Stack(
                fit: StackFit.expand,
                children: [
                  handoff.playback.buildView(),
                  VideoControls(playback: handoff.playback, actions: actions),
                ],
              )
            : placeholder,
      );
}
