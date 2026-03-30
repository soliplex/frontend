import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_agent/soliplex_agent.dart';

import 'package:soliplex_frontend/src/modules/room/ui/copy_button.dart';
import 'package:soliplex_frontend/src/modules/room/ui/error_message_tile.dart';

void main() {
  testWidgets('shows copy button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ErrorMessageTile(
            message: ErrorMessage(
              id: '1',
              createdAt: DateTime(2026),
              errorText: 'Something went wrong',
            ),
          ),
        ),
      ),
    );

    expect(find.byType(CopyButton), findsOneWidget);
  });
}
