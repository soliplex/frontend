import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/room/ui/unread_divider.dart';

void main() {
  testWidgets('renders the New messages label', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: UnreadDivider())),
    );
    expect(find.text('New messages'), findsOneWidget);
  });
}
