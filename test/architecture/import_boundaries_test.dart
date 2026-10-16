@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Enforces the layer order of ADR-005 (`docs/adr/ADR-005-module-layering.md`)
/// over `lib/src`: a unit may import only units in a lower layer, plus
/// itself. Feature modules share a layer and never import each other.
/// `mockups` sits outside the order: it may import anything, and nothing may
/// import it.
void main() {
  final edges = _scanEdges();
  final violations = [
    for (final edge in edges)
      if (_isViolation(edge)) '${edge.from} -> ${edge.to}',
  ]..sort();

  test('every lib/src directory has a layer', () {
    final unclassified = Directory('lib/src')
        .listSync()
        .whereType<Directory>()
        .expand(
          (dir) => _basename(dir.path) == 'modules'
              ? dir.listSync().whereType<Directory>()
              : [dir],
        )
        .map((dir) => _unitOf('${dir.path}/x.dart'))
        .where((unit) => unit != _mockups && !_layers.containsKey(unit))
        .toList();
    expect(
      unclassified,
      isEmpty,
      reason: 'Give each new unit a layer in _layers, per ADR-005.',
    );
  });

  test('no import goes against the layer order', () {
    expect(
      violations,
      isEmpty,
      reason: 'These imports break the layer order of ADR-005. Move the '
          'shared type down a layer (to stores/ or shared/) instead:\n'
          '${violations.join('\n')}',
    );
  });
}

const _mockups = 'mockups';

const _features = {
  'modules/lobby',
  'modules/room',
  'modules/quiz',
  'modules/diagnostics',
  'modules/versions',
};

/// Each unit's layer; a unit may import units in a lower layer. Units in one
/// layer may import each other, except feature modules.
final _layers = <String, int>{
  'shared': 0,
  'interfaces': 0,
  'core': 1,
  'status_message': 1,
  'modules/auth': 2,
  'stores': 3,
  for (final feature in _features) feature: 4,
  'flavors': 5,
};

typedef _Edge = ({String from, String to});

bool _isViolation(_Edge edge) {
  final from = _unitOf(edge.from);
  final to = _unitOf(edge.to);
  if (from == to || from == _mockups) return false;
  if (to == _mockups) return true;
  final fromLayer = _layers[from];
  final toLayer = _layers[to];
  // An unclassified unit fails the classification test instead.
  if (fromLayer == null || toLayer == null) return false;
  if (toLayer == fromLayer) {
    return _features.contains(from) && _features.contains(to);
  }
  return toLayer > fromLayer;
}

/// The unit a `lib/src` path belongs to: its top-level directory, or
/// `modules/<name>` for a module.
String _unitOf(String path) {
  final parts = path.substring('lib/src/'.length).split('/');
  return parts.first == 'modules' ? 'modules/${parts[1]}' : parts.first;
}

// The URI of an import or export, or of a conditional import's
// `if (dart.library.x) '...'` clause on a line of its own. Horizontal
// whitespace only, and a `.dart` URI, so a collection-if keyed by a string
// literal (`if (cond) 'key': value`) is not read as a URI.
final _directive = RegExp(
  r"""^[ \t]*(?:(?:import|export)[ \t]+|if[ \t]*\([\w.]+(?:[ \t]*==[ \t]*'[^'\n]*')?\)[ \t]*)'([^'\n]+\.dart)'""",
  multiLine: true,
);

const _packagePrefix = 'package:soliplex_frontend/';

/// Every import or export, conditional ones included, from one `lib/src`
/// file to another.
Set<_Edge> _scanEdges() {
  final edges = <_Edge>{};
  final files = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final from = file.path.replaceAll(r'\', '/');
    for (final match in _directive.allMatches(file.readAsStringSync())) {
      final uri = match.group(1)!;
      final to = _resolve(from, uri);
      if (to != null && to.startsWith('lib/src/')) {
        edges.add((from: from, to: to));
      }
    }
  }
  return edges;
}

/// The repo-relative path [uri] names when imported from [from], or null for
/// a `dart:` or other package's URI.
String? _resolve(String from, String uri) {
  if (uri.startsWith(_packagePrefix)) {
    return 'lib/${uri.substring(_packagePrefix.length)}';
  }
  if (uri.contains(':')) return null;
  final parts = from.split('/')..removeLast();
  for (final segment in uri.split('/')) {
    if (segment == '..') {
      parts.removeLast();
    } else if (segment != '.') {
      parts.add(segment);
    }
  }
  return parts.join('/');
}

String _basename(String path) => path.replaceAll(r'\', '/').split('/').last;
