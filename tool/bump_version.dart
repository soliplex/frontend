#!/usr/bin/env dart

/// Bumps the version in pubspec.yaml and syncs to lib/version.dart.
///
/// Usage:
/// ```sh
/// dart run tool/bump_version.dart <major|minor|patch|build>
/// ```
///
/// Examples:
/// ```sh
/// dart run tool/bump_version.dart patch  # 0.52.1+0 -> 0.52.2+1
/// dart run tool/bump_version.dart minor  # 0.52.1+0 -> 0.53.0+1
/// dart run tool/bump_version.dart major  # 0.52.1+0 -> 1.0.0+1
/// dart run tool/bump_version.dart build  # 0.52.1+0 -> 0.52.1+1
/// ```
library;

import 'dart:io';

void main(List<String> args) {
  if (args.isEmpty || !['major', 'minor', 'patch', 'build'].contains(args[0])) {
    stderr.writeln(
      'Usage: dart run tool/bump_version.dart <major|minor|patch|build>',
    );
    exit(1);
  }

  final bumpType = args[0];

  final pubspecFile = File('pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Error: pubspec.yaml not found. Run from project root.');
    exit(1);
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final versionMatch =
      RegExp(r'^version:\s*(.+)$', multiLine: true).firstMatch(pubspecContent);

  if (versionMatch == null) {
    stderr.writeln('Error: Could not find version in pubspec.yaml');
    exit(1);
  }

  final currentVersion = versionMatch.group(1)!.trim();
  final parsed = _parseVersion(currentVersion);
  if (parsed == null) {
    stderr
      ..writeln('Error: Invalid version format: $currentVersion')
      ..writeln('Expected format: X.Y.Z+N');
    exit(1);
  }

  final (major, minor, patch, build) = parsed;
  final newVersion = switch (bumpType) {
    'major' => '${major + 1}.0.0+${build + 1}',
    'minor' => '$major.${minor + 1}.0+${build + 1}',
    'patch' => '$major.$minor.${patch + 1}+${build + 1}',
    'build' => '$major.$minor.$patch+${build + 1}',
    _ => currentVersion,
  };

  // Update pubspec.yaml
  final newPubspecContent = pubspecContent.replaceFirst(
    RegExp(r'^version:\s*.+$', multiLine: true),
    'version: $newVersion',
  );
  pubspecFile.writeAsStringSync(newPubspecContent);
  stdout.writeln('Updated pubspec.yaml: $currentVersion -> $newVersion');

  // Run update_version.dart to sync lib/version.dart
  final result = Process.runSync(
    'dart',
    ['run', 'tool/update_version.dart'],
    runInShell: true,
  );

  if (result.exitCode != 0) {
    stderr
      ..writeln('Error running update_version.dart:')
      ..writeln(result.stderr);
    exit(1);
  }

  stdout.write(result.stdout);
}

/// Parses version string like "0.52.1+0" into (major, minor, patch, build).
(int, int, int, int)? _parseVersion(String version) {
  final match = RegExp(r'^(\d+)\.(\d+)\.(\d+)\+(\d+)$').firstMatch(version);
  if (match == null) return null;

  return (
    int.parse(match.group(1)!),
    int.parse(match.group(2)!),
    int.parse(match.group(3)!),
    int.parse(match.group(4)!),
  );
}
