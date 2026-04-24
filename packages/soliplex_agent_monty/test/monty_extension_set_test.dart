import 'package:dart_monty/dart_monty_bridge.dart'
    show MontyExtension, defaultExtensions;
import 'package:soliplex_agent_monty/soliplex_agent_monty.dart';
import 'package:test/test.dart';

void main() {
  group('MontyExtensionSet', () {
    test('standard returns dart_monty defaultExtensions', () {
      final set = MontyExtensionSet.standard();

      expect(set.all, isNotEmpty);
      // defaultExtensions is: JinjaTemplateExtension, MessageBusExtension,
      // EventLoopExtension (3 entries as of dart_monty 0.20.0).
      expect(set.all.length, 3);
      expect(set.all, everyElement(isA<MontyExtension>()));
    });

    test('standard returns a fresh list each call', () {
      // Mutating one list must not leak into the next.
      final a = MontyExtensionSet.standard();
      expect(a.all, isNotEmpty);
      final b = MontyExtensionSet.standard();
      expect(identical(a.all, b.all), isFalse);
    });

    test('direct constructor preserves ordering', () {
      final exts = <MontyExtension>[
        ...defaultExtensions(),
      ];
      final set = MontyExtensionSet(exts);

      expect(set.all, same(exts));
    });
  });
}
