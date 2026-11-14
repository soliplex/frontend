/// The file extensions a markdown image source is played as a video for.
///
/// Direct media only: `.m3u8` is an HLS playlist, which the player streams on
/// every platform. A page URL (YouTube, Vimeo) is not a video file and stays
/// whatever the markdown made it.
const _videoExtensions = {'mp4', 'webm', 'mov', 'm4v', 'm3u8'};

/// Whether [uri] is a network video file, which markdown image syntax
/// (`![caption](https://host/clip.mp4)`) renders as a player instead of an
/// image.
///
/// Only `http` and `https`: the backend serves no media of its own that a
/// player could reach without credentials, so a video in an answer is always
/// one the model linked from the web.
bool isVideoUri(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final path = uri.path;
  final dot = path.lastIndexOf('.');
  if (dot < 0 || dot < path.lastIndexOf('/')) return false;
  return _videoExtensions.contains(path.substring(dot + 1).toLowerCase());
}
