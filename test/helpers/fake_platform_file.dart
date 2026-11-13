import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:file_picker/file_picker.dart';

/// A picked file for tests, standing in for the platform packages' own
/// [PlatformFile] subclasses.
///
/// A [path] makes it a native pick, with a `file:` [uri]. Without one it
/// stands for a web pick: a `blob:` [uri] whose [bytes] are what the browser
/// read. [size] is what the platform reported at pick time, or `null` when
/// it reported nothing; [length] answers [readLength], which defaults to it.
base class FakePlatformFile extends PlatformFile {
  FakePlatformFile({
    required this.name,
    String? path,
    this.size,
    int? readLength,
    Uint8List? bytes,
    Object? readError,
  })  : uri = path != null
            ? Uri.file(path)
            : Uri.parse('blob:http://localhost/$name'),
        _readLength = readLength ?? size,
        _bytes = bytes,
        _readError = readError;

  @override
  final String name;

  @override
  final Uri uri;

  /// The size the platform reported at pick time.
  final int? size;

  final int? _readLength;
  final Uint8List? _bytes;
  final Object? _readError;

  @override
  XFile get xFile => XFile(uri.toString(), name: name, bytes: _bytes);

  @override
  int? lengthSync() => size;

  @override
  Future<int?> length() async => _readLength;

  @override
  Future<Uint8List> readAsBytes() async {
    final error = _readError;
    if (error != null) throw error;
    return _bytes ?? Uint8List(0);
  }

  @override
  Stream<Uint8List> readAsByteStream() async* {
    yield await readAsBytes();
  }
}
