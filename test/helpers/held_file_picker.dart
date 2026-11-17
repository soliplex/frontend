import 'dart:async';

import 'package:file_picker/file_picker.dart';

/// A platform picker whose answer the test gives when it chooses, by
/// completing [answer].
class HeldFilePicker extends FilePickerPlatform {
  final answer = Completer<List<PlatformFile>>();

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) =>
      answer.future;
}
