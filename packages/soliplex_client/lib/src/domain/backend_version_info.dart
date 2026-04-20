import 'package:meta/meta.dart';

/// Backend version information including all installed package versions.
@immutable
class BackendVersionInfo {
  /// Creates backend version info.
  const BackendVersionInfo({
    required this.soliplexVersion,
    required this.packageVersions,
  });

  /// The soliplex backend version.
  final String soliplexVersion;

  /// All installed package versions, keyed by package name.
  final Map<String, String> packageVersions;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BackendVersionInfo) return false;
    if (soliplexVersion != other.soliplexVersion) return false;
    if (packageVersions.length != other.packageVersions.length) return false;
    for (final key in packageVersions.keys) {
      if (packageVersions[key] != other.packageVersions[key]) return false;
    }
    return true;
  }

  @override
  int get hashCode {
    final sortedKeys = packageVersions.keys.toList()..sort();
    final sortedHashes = sortedKeys.map(
      (k) => Object.hash(k, packageVersions[k]),
    );
    return Object.hash(soliplexVersion, Object.hashAll(sortedHashes));
  }

  @override
  String toString() =>
      'BackendVersionInfo(soliplexVersion: $soliplexVersion, '
      'packageCount: ${packageVersions.length})';
}
