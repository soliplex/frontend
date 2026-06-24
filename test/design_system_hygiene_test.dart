@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guards the whitelabel contract's premise: app code never bakes in raw
/// colors, so a brand theme can recolor everything. Color belongs in the
/// `soliplex_design` tokens, reached through `Theme.of(context).colorScheme`,
/// `SoliplexTheme`, or the `context.danger/success/warning/info` accessors.
void main() {
  final dartFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  List<String> scan(RegExp pattern) {
    final offenders = <String>[];
    for (final file in dartFiles) {
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (pattern.hasMatch(lines[i])) offenders.add('${file.path}:${i + 1}');
      }
    }
    return offenders;
  }

  test('no raw hex color literals in app code', () {
    final offenders =
        scan(RegExp(r'Color\(0x|Color\.fromARGB|Color\.fromRGBO'));
    expect(
      offenders,
      isEmpty,
      reason: 'Hex colors belong in soliplex_design tokens:\n'
          '${offenders.join('\n')}',
    );
  });

  test('no hardcoded Material status colors in app code', () {
    final offenders = scan(RegExp(r'Colors\.(red|green|orange|blue|yellow)\b'));
    expect(
      offenders,
      isEmpty,
      reason: 'Use context.danger/success/warning/info instead:\n'
          '${offenders.join('\n')}',
    );
  });
}
