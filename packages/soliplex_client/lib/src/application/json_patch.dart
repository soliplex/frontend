import 'package:soliplex_logging/soliplex_logging.dart';

final Logger _defaultLogger =
    LogManager.instance.getLogger('soliplex_client.json_patch');

/// The patched state, and whether no operation in the patch was skipped. When
/// one was, the state may differ from the one the patch's producer ended with.
typedef JsonPatchResult = ({Map<String, dynamic> state, bool complete});

const _operationNames = {'add', 'remove', 'replace', 'move', 'copy', 'test'};

/// An operation this file does not apply. The reason is this file's own text,
/// never a value from the patch.
class _Unappliable implements Exception {
  const _Unappliable(this.reason);

  final String reason;
}

/// Applies RFC 6902 JSON Patch operations to a state map.
///
/// Returns the patched state as a new map, and whether any operation was
/// skipped. An operation that cannot be applied is logged via [logger] and
/// skipped so the rest of the patch can land, and the result is marked
/// incomplete. Supports `add`, `replace` and `remove`; `move`, `copy` and
/// `test` are skipped, because no supported backend sends them.
///
/// Some operations RFC 6902 treats as errors are applied instead: removing an
/// absent map key, or a map key under an absent one, which leaves it absent;
/// `replace` of an absent map key, which sets it; and `add` or `replace` under
/// absent containers, which are created. A list position under an absent
/// container is skipped: the producer's list shifted, and this state has none.
///
/// A skip with a path is logged by the path's first segment and depth only: a
/// path can carry values, such as the search queries `rag.searches` is keyed
/// by.
JsonPatchResult applyJsonPatch(
  Map<String, dynamic> state,
  List<dynamic> operations, {
  Logger? logger,
}) {
  final log = logger ?? _defaultLogger;
  var result = Map<String, dynamic>.from(state);
  var complete = true;

  for (final op in operations) {
    if (op is! Map<String, dynamic>) {
      complete = false;
      log.warning(
        'JSON Patch operation skipped: not an object',
        attributes: {'runtimeType': '${op.runtimeType}'},
      );
      continue;
    }
    final operation = op['op'];
    final path = op['path'];
    if (operation is! String || path is! String) {
      complete = false;
      log.warning(
        'JSON Patch operation skipped: missing op or path',
        attributes: {
          'opType': '${operation.runtimeType}',
          'pathType': '${path.runtimeType}',
        },
      );
      continue;
    }
    try {
      result = switch (operation) {
        'add' => _setAtPath(result, path, op['value'], insert: true),
        'replace' => _setAtPath(result, path, op['value']),
        'remove' => _removeAtPath(result, path),
        _ => throw const _Unappliable('unsupported operation'),
      };
    } on Object catch (error, stackTrace) {
      complete = false;
      final segments = _parsePath(path);
      log.warning(
        'JSON Patch operation skipped',
        stackTrace: stackTrace,
        attributes: {
          'op': _operationNames.contains(operation) ? operation : 'unknown',
          'namespace': segments.isEmpty ? '/' : segments.first,
          'depth': segments.length,
          'failure':
              error is _Unappliable ? error.reason : describeFailure(error),
        },
      );
    }
  }

  return (state: result, complete: complete);
}

Map<String, dynamic> _setAtPath(
  Map<String, dynamic> state,
  String path,
  dynamic value, {
  bool insert = false,
}) {
  final segments = _parsePath(path);
  if (segments.isEmpty) {
    // Path "" or "/" replaces the root, which must stay a map.
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    throw const _Unappliable('root replaced by a non-object');
  }

  final result = _deepCopy(state);
  dynamic current = result;

  for (var i = 0; i < segments.length - 1; i++) {
    final segment = segments[i];
    if (current is Map<String, dynamic>) {
      if (current[segment] == null) {
        current[segment] = _isListPosition(segments[i + 1])
            ? <dynamic>[]
            : <String, dynamic>{};
      }
      current = current[segment];
    } else if (current is List) {
      current = _listElement(current, segment);
    } else {
      throw const _Unappliable('path does not exist');
    }
  }

  final lastSegment = segments.last;
  if (current is Map<String, dynamic>) {
    current[lastSegment] = value;
  } else if (current is List) {
    // "-" appends: RFC 6902 defines it for add, and replace takes it too.
    if (lastSegment == '-') {
      current.add(value);
    } else {
      final index = int.tryParse(lastSegment);
      if (index == null) {
        throw const _Unappliable('array index is not a number');
      }
      if (insert && index >= 0 && index <= current.length) {
        // RFC 6902 §4.1: add inserts before the index, shifting elements.
        current.insert(index, value);
      } else if (!insert && index >= 0 && index < current.length) {
        current[index] = value;
      } else {
        throw const _Unappliable('array index out of bounds');
      }
    }
  } else {
    throw const _Unappliable('path does not exist');
  }

  return result;
}

Map<String, dynamic> _removeAtPath(Map<String, dynamic> state, String path) {
  final segments = _parsePath(path);
  if (segments.isEmpty) {
    throw const _Unappliable('the root cannot be removed');
  }

  final result = _deepCopy(state);
  dynamic current = result;

  for (var i = 0; i < segments.length - 1; i++) {
    final segment = segments[i];
    if (current is Map<String, dynamic>) {
      final next = current[segment];
      if (next == null) {
        // A list position under an absent container shifted the producer's
        // list; an absent key under one is already what the producer holds.
        if (_isListPosition(segments.last)) {
          throw const _Unappliable('path does not exist');
        }
        return result;
      }
      current = next;
    } else if (current is List) {
      current = _listElement(current, segment);
    } else {
      throw const _Unappliable('path does not exist');
    }
  }

  final lastSegment = segments.last;
  if (current is Map<String, dynamic>) {
    current.remove(lastSegment);
  } else if (current is List) {
    final index = int.tryParse(lastSegment);
    if (index == null) {
      throw const _Unappliable('array index is not a number');
    }
    if (index < 0 || index >= current.length) {
      throw const _Unappliable('array index out of bounds');
    }
    current.removeAt(index);
  } else {
    throw const _Unappliable('path does not exist');
  }

  return result;
}

/// The element of [list] that [segment], one step of a path, names.
dynamic _listElement(List<dynamic> list, String segment) {
  final index = int.tryParse(segment);
  if (index == null || index < 0 || index >= list.length) {
    throw const _Unappliable('path does not exist');
  }
  return list[index];
}

bool _isListPosition(String segment) =>
    segment == '-' || int.tryParse(segment) != null;

/// The decoded segments of [path]. `""` and `"/"` are the root; any other
/// empty segment is the key `""`, as RFC 6901 reads it.
List<String> _parsePath(String path) {
  if (path.isEmpty || path == '/') return [];
  final pointer = path.startsWith('/') ? path.substring(1) : path;
  return [
    for (final segment in pointer.split('/'))
      // RFC 6901: `~1` before `~0`, so `~01` reads as a literal `~1`.
      segment.replaceAll('~1', '/').replaceAll('~0', '~'),
  ];
}

Map<String, dynamic> _deepCopy(Map<String, dynamic> map) {
  return map.map((key, value) {
    if (value is Map<String, dynamic>) {
      return MapEntry(key, _deepCopy(value));
    } else if (value is List) {
      return MapEntry(key, _deepCopyList(value));
    }
    return MapEntry(key, value);
  });
}

List<dynamic> _deepCopyList(List<dynamic> list) {
  return list.map((item) {
    if (item is Map<String, dynamic>) {
      return _deepCopy(item);
    } else if (item is List) {
      return _deepCopyList(item);
    }
    return item;
  }).toList();
}
