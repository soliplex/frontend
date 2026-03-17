import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/main.dart' as app;

void main() {
  testWidgets('app boots and renders home screen', (tester) async {
    app.main();
    await tester.pumpAndSettle();

    expect(find.text('Soliplex'), findsOneWidget);
  });
}
