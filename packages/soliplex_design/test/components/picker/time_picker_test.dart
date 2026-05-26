import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    theme: soliplexLightTheme(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

void main() {
  testWidgets('renders the formatted initial time and clock icon',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexTimePickerField(
          label: 'Reminder',
          initialValue: TimeOfDay(hour: 9, minute: 0),
        ),
      ),
    );
    expect(find.byIcon(Icons.schedule_outlined), findsOneWidget);
    // Locale-formatted time should contain a colon between hour and minute.
    expect(find.textContaining(':'), findsOneWidget);
  });

  testWidgets('isLoading swaps the trailing icon for a spinner',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexTimePickerField(label: 'Reminder', isLoading: true),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.schedule_outlined), findsNothing);
  });

  testWidgets('opens the picker on tap', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexTimePickerField(
          label: 'Reminder',
          initialValue: TimeOfDay(hour: 9, minute: 0),
        ),
      ),
    );
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    // showTimePicker opens its own dialog. Cancel to dismiss without
    // exercising the keypad-vs-dial fork.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });
}
