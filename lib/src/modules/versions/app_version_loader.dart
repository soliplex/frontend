import 'package:package_info_plus/package_info_plus.dart';

typedef AppVersionLoader = Future<String> Function();

/// Formats as `<version>+<buildNumber>` to match `pubspec.yaml`'s `version:`
/// field.
Future<String> loadFlavorVersion() async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version}+${info.buildNumber}';
}
