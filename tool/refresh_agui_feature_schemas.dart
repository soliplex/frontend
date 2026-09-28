#!/usr/bin/env dart

/// Writes the drift-test snapshot of the AG-UI feature schemas a backend
/// checkout publishes, named for the haiku.rag version that checkout runs.
///
/// Usage, from the repository root:
/// ```sh
/// dart run tool/refresh_agui_feature_schemas.dart <clean backend worktree>
/// ```
///
/// The checkout's environment must be synced (`uv sync`), so that
/// `.venv/bin/soliplex-cli` exists. When to refresh and which checkout gives
/// each snapshot: `docs/refreshing-backend-schema-snapshots.md`.
library;

import 'dart:convert';
import 'dart:io';

const _snapshotDir =
    'packages/soliplex_client/test/schema/fixtures/agui_feature_schemas';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/refresh_agui_feature_schemas.dart '
      '<clean backend worktree>',
    );
    exit(64);
  }
  if (!File('pubspec.yaml').existsSync() ||
      !Directory('packages/soliplex_client').existsSync()) {
    stderr.writeln('Error: run from the repository root.');
    exit(1);
  }
  final backend = Directory(args.single).absolute.path;
  final cli = '$backend/.venv/bin/soliplex-cli';
  final python = '$backend/.venv/bin/python';
  if (!File(cli).existsSync()) {
    stderr.writeln('Error: $cli not found; run `uv sync` in the checkout.');
    exit(1);
  }
  final status = _run(
    'git',
    ['status', '--porcelain'],
    backend,
  ).trim();
  if (status.isNotEmpty) {
    stderr.writeln(
      'Error: $backend has uncommitted changes or untracked files; export '
      'from a clean worktree.',
    );
    exit(1);
  }

  final haikuRag = _run(
    python,
    [
      '-c',
      "import importlib.metadata as m; print(m.version('haiku.rag-slim'))",
    ],
    backend,
  ).trim();
  final commit = _run('git', ['rev-parse', 'HEAD'], backend).trim();
  // The export builds the installation's config and contacts no model, but
  // example/minimal.yaml names OLLAMA_BASE_URL without a default.
  final environment = {
    if (!Platform.environment.containsKey('OLLAMA_BASE_URL'))
      'OLLAMA_BASE_URL': 'http://localhost:11434',
  };
  final features = jsonDecode(
    _run(
      cli,
      ['agui-feature-schemas', 'example/minimal.yaml'],
      backend,
      environment: environment,
    ),
  );

  Directory(_snapshotDir).createSync(recursive: true);
  final out = File('$_snapshotDir/haiku-rag-$haikuRag.json');
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
          'haiku_rag': haikuRag,
          'backend_commit': commit,
          'features': features,
        })}\n',
  );
  stdout.writeln('Wrote ${out.path}');
}

String _run(
  String executable,
  List<String> arguments,
  String workingDirectory, {
  Map<String, String> environment = const {},
}) {
  final result = Process.runSync(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
  if (result.exitCode != 0) {
    stderr
      ..writeln('Error: $executable ${arguments.join(' ')} '
          'exited ${result.exitCode}')
      ..writeln(result.stderr);
    exit(1);
  }
  return result.stdout as String;
}
