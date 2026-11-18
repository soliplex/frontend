/// The file extensions a markdown image source is played as a video for.
///
/// Media files, and HLS playlists (`.m3u8`), which the player streams on
/// every platform. A page URL (YouTube, Vimeo) is not a video file and stays
/// whatever the markdown made it.
const _videoExtensions = {'mp4', 'webm', 'mov', 'm4v', 'm3u8'};

/// Whether [uri] is a network video file, which markdown image syntax
/// (`![caption](https://host/clip.mp4)`) renders as a player instead of an
/// image.
///
/// Only `http` and `https`: the players fetch the source over the network,
/// and a `file:`, `data:` or relative source is not one they can.
bool isVideoUri(Uri uri) {
  if (uri.scheme != 'http' && uri.scheme != 'https') return false;
  final path = uri.path;
  final extension = path.substring(path.lastIndexOf('.') + 1).toLowerCase();
  return _videoExtensions.contains(extension);
}

/// What a log record says of the video at [uri]: its host and path, and only
/// the length of its query, where a signed media URL carries its credential.
Map<String, Object> videoSourceAttributes(Uri uri) => {
      'host': uri.host,
      'path': uri.path,
      'queryLength': uri.query.length,
    };
