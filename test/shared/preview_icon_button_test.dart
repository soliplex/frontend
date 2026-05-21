import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/shared/preview_icon_button.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders an eye icon with a Preview tooltip by default',
      (tester) async {
    await tester.pumpWidget(_wrap(PreviewIconButton(onTap: () {})));

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byTooltip('Preview'), findsOneWidget);
  });

  testWidgets('uses the provided tooltip', (tester) async {
    await tester.pumpWidget(_wrap(
      PreviewIconButton(onTap: () {}, tooltip: 'View source PDF'),
    ));

    expect(find.byTooltip('View source PDF'), findsOneWidget);
  });

  testWidgets('invokes onTap on press', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_wrap(PreviewIconButton(onTap: () => taps++)));

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    expect(taps, 1);
  });

  testWidgets('null onTap is reported as a disabled button in semantics',
      (tester) async {
    final handle = tester.ensureSemantics();

    await tester.pumpWidget(_wrap(const PreviewIconButton(onTap: null)));

    expect(
      tester.getSemantics(find.byType(PreviewIconButton)),
      matchesSemantics(
        label: 'Preview',
        isButton: true,
        hasEnabledState: true,
        // No isEnabled — onTap is null so the button reports disabled.
      ),
    );

    handle.dispose();
  });
}
