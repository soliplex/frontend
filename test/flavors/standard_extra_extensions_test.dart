import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

/// Covers the composition pattern `standard()` uses for the
/// `extraExtensions` hook: `[...builtIns, ...await extras?.call() ?? []]`.
///
/// `standard()` itself wires real HTTP, storage, and auth layers, so it
/// is exercised via the running app rather than a widget test. This
/// test locks in the composition contract that `standard()` relies on —
/// if it drifts (e.g., extras are prepended instead of appended, or a
/// `null` factory raises), the pattern is wrong and `standard()` will
/// misbehave in the same way.
///
/// Keep the composition shape in `lib/src/flavors/standard.dart` in
/// sync with [composeExtensions].
Future<List<SessionExtension>> composeExtensions(
  List<SessionExtension> builtIns,
  SessionExtensionFactory? extras,
) async {
  return [
    ...builtIns,
    ...?(await extras?.call()),
  ];
}

class _FakeExtension implements SessionExtension {
  _FakeExtension(this.name);
  final String name;
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

void main() {
  group('standard() extraExtensions composition', () {
    test('null extras returns the built-in list unchanged', () async {
      final builtIns = <SessionExtension>[_FakeExtension('a')];
      final composed = await composeExtensions(builtIns, null);
      expect(composed, hasLength(1));
      expect((composed.single as _FakeExtension).name, 'a');
    });

    test('extras append after built-ins', () async {
      final builtIns = <SessionExtension>[
        _FakeExtension('a'),
        _FakeExtension('b'),
      ];
      final composed = await composeExtensions(
        builtIns,
        () async => [_FakeExtension('c')],
      );
      expect(
        composed.map((e) => (e as _FakeExtension).name).toList(),
        ['a', 'b', 'c'],
      );
    });

    test('empty extras list preserves built-ins', () async {
      final builtIns = <SessionExtension>[_FakeExtension('a')];
      final composed = await composeExtensions(
        builtIns,
        () async => <SessionExtension>[],
      );
      expect(composed, hasLength(1));
    });

    test('factory is awaited fresh on each call', () async {
      var callCount = 0;
      Future<List<SessionExtension>> factory() async {
        callCount++;
        return [_FakeExtension('n$callCount')];
      }

      final first = await composeExtensions(const [], factory);
      final second = await composeExtensions(const [], factory);
      expect((first.single as _FakeExtension).name, 'n1');
      expect((second.single as _FakeExtension).name, 'n2');
      expect(callCount, 2);
    });
  });
}
