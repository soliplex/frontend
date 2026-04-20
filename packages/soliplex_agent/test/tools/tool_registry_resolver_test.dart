import 'dart:convert';

import 'package:soliplex_agent/soliplex_agent.dart';
import 'package:soliplex_agent/src/tools/tool_registry_resolver.dart';
import 'package:test/test.dart';

import '../helpers/fake_tool_execution_context.dart';

final _ctx = FakeToolExecutionContext();

void main() {
  group('ToolRegistryResolver', () {
    group('typedef contract', () {
      test('resolver returns a ToolRegistry for a given room ID', () async {
        Future<ToolRegistry> resolver(String roomId) async {
          return const ToolRegistry();
        }

        final registry = await resolver('room-1');
        expect(registry, isA<ToolRegistry>());
        expect(registry.isEmpty, isTrue);
      });

      test('resolver can return different registries per room', () async {
        Future<ToolRegistry> resolver(String roomId) async {
          var registry = const ToolRegistry();
          if (roomId == 'room-with-tools') {
            registry = registry.register(
              ClientTool(
                definition: const Tool(
                  name: 'weather',
                  description: 'Get weather',
                ),
                executor: (call, _) async => '{"temp": 72}',
              ),
            );
          }
          return registry;
        }

        final emptyRegistry = await resolver('room-no-tools');
        final toolRegistry = await resolver('room-with-tools');

        expect(emptyRegistry.isEmpty, isTrue);
        expect(toolRegistry.length, equals(1));
        expect(toolRegistry.contains('weather'), isTrue);
      });
    });

    group('register → lookup → execute flow', () {
      late ToolRegistry registry;

      setUp(() {
        registry = const ToolRegistry()
            .register(
              ClientTool(
                definition: const Tool(
                  name: 'get_location',
                  description: 'Get GPS coordinates',
                  parameters: {
                    'type': 'object',
                    'properties': {
                      'format': {
                        'type': 'string',
                        'enum': ['dms', 'decimal'],
                      },
                    },
                  },
                ),
                executor: (call, _) async {
                  final args = jsonDecode(call.arguments) as Map;
                  final format = args['format'] as String? ?? 'decimal';
                  if (format == 'dms') {
                    return "40°44'N 73°59'W";
                  }
                  return '{"lat": 40.7128, "lng": -74.0060}';
                },
              ),
            )
            .register(
              ClientTool(
                definition: const Tool(
                  name: 'clipboard_read',
                  description: 'Read clipboard contents',
                ),
                executor: (call, _) async => 'clipboard text',
              ),
            );
      });

      test('registers multiple tools', () {
        expect(registry.length, equals(2));
        expect(registry.contains('get_location'), isTrue);
        expect(registry.contains('clipboard_read'), isTrue);
      });

      test('looks up a registered tool', () {
        final tool = registry.lookup('get_location');
        expect(tool.definition.name, equals('get_location'));
        expect(tool.definition.description, equals('Get GPS coordinates'));
      });

      test('executes tool with JSON arguments', () async {
        final result = await registry.execute(
          const ToolCallInfo(
            id: 'tc-1',
            name: 'get_location',
            arguments: '{"format": "decimal"}',
          ),
          _ctx,
        );

        final parsed = jsonDecode(result) as Map<String, dynamic>;
        expect(parsed['lat'], equals(40.7128));
        expect(parsed['lng'], equals(-74.0060));
      });

      test('executes tool with different arguments', () async {
        final result = await registry.execute(
          const ToolCallInfo(
            id: 'tc-2',
            name: 'get_location',
            arguments: '{"format": "dms"}',
          ),
          _ctx,
        );

        expect(result, contains('40°44'));
      });

      test('executes a different tool', () async {
        final result = await registry.execute(
          const ToolCallInfo(id: 'tc-3', name: 'clipboard_read'),
          _ctx,
        );

        expect(result, equals('clipboard text'));
      });

      test('exports tool definitions for backend', () {
        final definitions = registry.toolDefinitions;
        expect(definitions, hasLength(2));

        final names = definitions.map((d) => d.name).toSet();
        expect(names, containsAll(['get_location', 'clipboard_read']));
      });
    });

    group('error handling', () {
      test('lookup throws StateError for unknown tool', () {
        const registry = ToolRegistry();

        expect(
          () => registry.lookup('nonexistent'),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('nonexistent'),
            ),
          ),
        );
      });

      test('execute throws StateError for unknown tool', () {
        const registry = ToolRegistry();

        expect(
          () => registry.execute(
            const ToolCallInfo(id: 'tc-1', name: 'missing_tool'),
            _ctx,
          ),
          throwsA(isA<StateError>()),
        );
      });

      test('executor exception propagates to caller', () {
        final registry = const ToolRegistry().register(
          ClientTool(
            definition: const Tool(
              name: 'fail_tool',
              description: 'Always fails',
            ),
            executor:
                (call, _) async => throw Exception('Tool execution failed'),
          ),
        );

        expect(
          () => registry.execute(
            const ToolCallInfo(id: 'tc-1', name: 'fail_tool'),
            _ctx,
          ),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Tool execution failed'),
            ),
          ),
        );
      });
    });

    group('resolver with room-scoped tools', () {
      late ToolRegistryResolver resolver;
      late Map<String, List<ClientTool>> roomTools;

      setUp(() {
        roomTools = {
          'weather-room': [
            ClientTool(
              definition: const Tool(
                name: 'get_weather',
                description: 'Get current weather',
                parameters: {
                  'type': 'object',
                  'properties': {
                    'city': {'type': 'string'},
                  },
                  'required': ['city'],
                },
              ),
              executor: (call, _) async {
                final args = jsonDecode(call.arguments) as Map;
                return '{"city": "${args['city']}", "temp": 72}';
              },
            ),
          ],
          'file-room': [
            ClientTool(
              definition: const Tool(
                name: 'file_picker',
                description: 'Pick a file',
              ),
              executor: (call, _) async => '/path/to/file.txt',
            ),
            ClientTool(
              definition: const Tool(
                name: 'file_read',
                description: 'Read file contents',
              ),
              executor: (call, _) async => 'file contents here',
            ),
          ],
        };

        resolver = (roomId) async {
          final tools = roomTools[roomId] ?? [];
          var registry = const ToolRegistry();
          for (final tool in tools) {
            registry = registry.register(tool);
          }
          return registry;
        };
      });

      test('resolves room with one tool', () async {
        final registry = await resolver('weather-room');
        expect(registry.length, equals(1));
        expect(registry.contains('get_weather'), isTrue);
      });

      test('resolves room with multiple tools', () async {
        final registry = await resolver('file-room');
        expect(registry.length, equals(2));
        expect(registry.contains('file_picker'), isTrue);
        expect(registry.contains('file_read'), isTrue);
      });

      test('resolves unknown room to empty registry', () async {
        final registry = await resolver('unknown-room');
        expect(registry.isEmpty, isTrue);
      });

      test('end-to-end: resolve then execute', () async {
        final registry = await resolver('weather-room');

        final result = await registry.execute(
          const ToolCallInfo(
            id: 'tc-1',
            name: 'get_weather',
            arguments: '{"city": "NYC"}',
          ),
          _ctx,
        );

        final parsed = jsonDecode(result) as Map<String, dynamic>;
        expect(parsed['city'], equals('NYC'));
        expect(parsed['temp'], equals(72));
      });

      test('resolver is async to support IO-bound lookups', () async {
        Future<ToolRegistry> asyncResolver(String roomId) async {
          // Simulate network delay for fetching room config
          await Future<void>.delayed(Duration.zero);
          return const ToolRegistry().register(
            ClientTool(
              definition: const Tool(
                name: 'delayed_tool',
                description: 'Async-resolved tool',
              ),
              executor: (call, _) async => 'async result',
            ),
          );
        }

        final registry = await asyncResolver('any-room');
        expect(registry.contains('delayed_tool'), isTrue);
      });
    });

    group('immutability', () {
      test('register returns new registry without mutating original', () {
        const original = ToolRegistry();
        final updated = original.register(
          ClientTool(
            definition: const Tool(name: 'tool_a', description: 'Tool A'),
            executor: (call, _) async => 'a',
          ),
        );

        expect(original.isEmpty, isTrue);
        expect(updated.length, equals(1));
      });

      test('chained registers build up incrementally', () {
        final registry = const ToolRegistry()
            .register(
              ClientTool(
                definition: const Tool(name: 'tool_1', description: 'First'),
                executor: (call, _) async => '1',
              ),
            )
            .register(
              ClientTool(
                definition: const Tool(name: 'tool_2', description: 'Second'),
                executor: (call, _) async => '2',
              ),
            )
            .register(
              ClientTool(
                definition: const Tool(name: 'tool_3', description: 'Third'),
                executor: (call, _) async => '3',
              ),
            );

        expect(registry.length, equals(3));
      });
    });
  });
}
