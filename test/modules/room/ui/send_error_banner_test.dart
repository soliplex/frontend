import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/send_error.dart';
import 'package:soliplex_frontend/src/modules/room/ui/send_error_banner.dart';

void main() {
  testWidgets('a focused copy shows its highlight over the tint',
      (tester) async {
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic);
    await tester.pumpWidget(MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: SendErrorBanner(
          error: const SendError('Not permitted to run in this room'),
          onDismiss: () {},
        ),
      ),
    ));
    final copy = tester.element(find.byIcon(Icons.copy));
    final theme = Theme.of(copy);

    Focus.of(copy).requestFocus();
    await tester.pumpAndSettle();

    // An InkWell draws its highlights on the Material beneath it: the tint
    // must be drawn there too, first, or it covers them.
    expect(
      Material.of(copy) as RenderObject,
      paints
        ..rect(color: theme.colorScheme.errorContainer)
        ..rrect(color: theme.focusColor),
    );
  });
}
