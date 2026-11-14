import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/shared/video/video_uri.dart';

void main() {
  bool video(String source) => isVideoUri(Uri.parse(source));

  test('plays network video files', () {
    expect(video('https://cdn.example/clip.mp4'), isTrue);
    expect(video('http://cdn.example/a/b/clip.webm'), isTrue);
    expect(video('https://cdn.example/clip.mov'), isTrue);
    expect(video('https://cdn.example/clip.m4v'), isTrue);
    expect(video('https://cdn.example/live/index.m3u8'), isTrue);
  });

  test('reads the extension whatever its case', () {
    expect(video('https://cdn.example/CLIP.MP4'), isTrue);
  });

  test('reads the path, not the query or fragment', () {
    expect(video('https://cdn.example/clip.mp4?sig=abc&exp=1'), isTrue);
    expect(video('https://cdn.example/clip.mp4#t=10'), isTrue);
    expect(video('https://cdn.example/watch?v=clip.mp4'), isFalse);
  });

  test('leaves images and pages alone', () {
    expect(video('https://cdn.example/photo.png'), isFalse);
    expect(video('https://www.youtube.com/watch?v=abc'), isFalse);
    expect(video('https://cdn.example/'), isFalse);
    expect(video('https://cdn.example/mp4'), isFalse);
    expect(video('https://cdn.example/clip.mp4/'), isFalse);
  });

  test('plays nothing that is not on the network', () {
    expect(video('file:///tmp/clip.mp4'), isFalse);
    expect(video('resource:clip.mp4'), isFalse);
    expect(video('/v1/uploads/room/file/clip.mp4'), isFalse);
    expect(video('data:video/mp4;base64,AAAA'), isFalse);
  });
}
