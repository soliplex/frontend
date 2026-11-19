sealed class JsonNode {
  const JsonNode({required this.key});

  final String key;
}

final class ValueNode extends JsonNode {
  const ValueNode({required super.key, required this.value});

  /// The decoded scalar: a String, num, bool or null.
  final Object? value;
}

final class ObjectNode extends JsonNode {
  const ObjectNode({required super.key, required this.children});

  final List<JsonNode> children;
}

final class ArrayNode extends JsonNode {
  const ArrayNode({required super.key, required this.children});

  final List<JsonNode> children;

  int get itemCount => children.length;
}

/// The nodes of [json]. It recurses once per nesting level and does not bound
/// depth, so callers check depth first.
List<JsonNode> buildJsonTree(dynamic json, {String rootKey = ''}) {
  if (json is Map) {
    return json.entries.map((e) => _buildNode('${e.key}', e.value)).toList();
  }
  if (json is List) {
    return _buildArrayChildren(json);
  }
  return [ValueNode(key: rootKey, value: json)];
}

JsonNode _buildNode(String key, dynamic value) {
  if (value is Map) {
    return ObjectNode(
      key: key,
      children:
          value.entries.map((e) => _buildNode('${e.key}', e.value)).toList(),
    );
  }
  if (value is List) {
    return ArrayNode(
      key: key,
      children: _buildArrayChildren(value),
    );
  }
  return ValueNode(key: key, value: value);
}

List<JsonNode> _buildArrayChildren(List<dynamic> list) {
  return [for (var i = 0; i < list.length; i++) _buildNode('[$i]', list[i])];
}
