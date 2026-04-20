#!/usr/bin/env dart

/// Updates lib/version.dart with the version from pubspec.yaml.
///
/// Run this script after changing the version in pubspec.yaml:
/// ```sh
/// dart run tool/update_version.dart
/// ```
library;

import 'dart:io';

void main() {
  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found. Run from project root.');
    exit(1);
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final versionMatch = RegExp(
    r'^version:\s*(.+)$',
    multiLine: true,
  ).firstMatch(pubspecContent);

  if (versionMatch == null) {
    stderr.writeln('Error: Could not find version in pubspec.yaml');
    exit(1);
  }

  final version = versionMatch.group(1)!.trim();

  // Validate version format (e.g., 0.52.1+0 or 0.52.1)
  if (!RegExp(r'^\d+\.\d+\.\d+(\+\d+)?$').hasMatch(version)) {
    stderr
      ..writeln('Error: Invalid version format: $version')
      ..writeln('Expected format: X.Y.Z or X.Y.Z+N');
    exit(1);
  }

  final versionFileContent = '''
/// Soliplex library version.
///
/// Generated from pubspec.yaml. Run `dart run tool/update_version.dart` after
/// changing the version in pubspec.yaml.
const String soliplexVersion = '$version';
''';

  File('lib/version.dart').writeAsStringSync(versionFileContent);

  stdout.writeln('Updated lib/version.dart to version $version');
}
