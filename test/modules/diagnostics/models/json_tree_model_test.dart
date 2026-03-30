import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/diagnostics/models/json_tree_model.dart';

void main() {
  group('buildJsonTree', () {
    test('builds ValueNodes from map', () {
      final nodes = buildJsonTree({'name': 'Alice', 'age': 30});
      expect(nodes, hasLength(2));
      expect(nodes[0], isA<ValueNode>());
      expect((nodes[0] as ValueNode).key, 'name');
      expect((nodes[0] as ValueNode).value, 'Alice');
      expect(nodes[1], isA<ValueNode>());
      expect((nodes[1] as ValueNode).key, 'age');
      expect((nodes[1] as ValueNode).value, '30');
    });

    test('builds ArrayNode from list', () {
      final nodes = buildJsonTree({
        'items': [1, 2, 3]
      });
      expect(nodes, hasLength(1));
      expect(nodes[0], isA<ArrayNode>());
      final arr = nodes[0] as ArrayNode;
      expect(arr.key, 'items');
      expect(arr.itemCount, 3);
      expect(arr.children, hasLength(3));
    });

    test('builds nested ObjectNode', () {
      final nodes = buildJsonTree({
        'user': {
          'name': 'Alice',
          'address': {'city': 'NYC'},
        },
      });
      expect(nodes, hasLength(1));
      expect(nodes[0], isA<ObjectNode>());
      final user = nodes[0] as ObjectNode;
      expect(user.key, 'user');
      expect(user.children, hasLength(2));
    });

    test('handles null values', () {
      final nodes = buildJsonTree({'key': null});
      expect(nodes, hasLength(1));
      expect(nodes[0], isA<ValueNode>());
      expect((nodes[0] as ValueNode).value, 'null');
    });

    test('handles empty map', () {
      final nodes = buildJsonTree({});
      expect(nodes, isEmpty);
    });

    test('handles empty list', () {
      final nodes = buildJsonTree({'empty': []});
      expect(nodes, hasLength(1));
      expect(nodes[0], isA<ArrayNode>());
      expect((nodes[0] as ArrayNode).itemCount, 0);
    });

    test('builds from top-level list', () {
      final nodes = buildJsonTree([1, 'two', true]);
      expect(nodes, hasLength(3));
      expect(nodes[0], isA<ValueNode>());
      expect((nodes[0] as ValueNode).key, '[0]');
      expect((nodes[0] as ValueNode).value, '1');
    });

    test('handles primitive top-level value', () {
      final nodes = buildJsonTree('just a string');
      expect(nodes, hasLength(1));
      expect(nodes[0], isA<ValueNode>());
      expect((nodes[0] as ValueNode).value, 'just a string');
    });

    test('handles boolean and numeric values', () {
      final nodes = buildJsonTree({'flag': true, 'count': 42, 'rate': 3.14});
      expect(nodes, hasLength(3));
      expect((nodes[0] as ValueNode).value, 'true');
      expect((nodes[1] as ValueNode).value, '42');
      expect((nodes[2] as ValueNode).value, '3.14');
    });
  });
}
