import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/shared/selectable_content.dart';

void main() {
  testWidgets('keyboard traversal skips the selectable region', (tester) async {
    final first = FocusNode(debugLabel: 'first');
    final second = FocusNode(debugLabel: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                  focusNode: first, onPressed: () {}, child: const Text('one')),
              const SelectableContent(child: Text('an error worth copying')),
              TextButton(
                focusNode: second,
                onPressed: () {},
                child: const Text('two'),
              ),
            ],
          ),
        ),
      ),
    );

    first.requestFocus();
    await tester.pump();
    expect(primaryFocus, first);

    // The region paints no focus ring, so a stop on it would look like the
    // keyboard had vanished. Tab has to reach the next real control.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(primaryFocus, second);
  });

  testWidgets('a tap inside still reaches a handler underneath',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SelectableContent(
            child: GestureDetector(
              onTap: () => taps++,
              behavior: HitTestBehavior.opaque,
              child: const Text('tap me'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('tap me'));
    await tester.pump();

    expect(taps, 1);
  });
}
