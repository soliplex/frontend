import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/main.dart' as app;

void main() {
  testWidgets('app renders Soliplex text', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('Soliplex'), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
