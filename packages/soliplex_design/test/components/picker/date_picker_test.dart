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
  testWidgets('renders the formatted initial value', (tester) async {
    final date = DateTime(2026, 5, 26);
    await tester.pumpWidget(
      _harness(
        SoliplexDatePickerField(label: 'Start', initialValue: date),
      ),
    );
    // Locale-formatted full date includes the year so check for 2026.
    expect(find.textContaining('2026'), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
  });

  testWidgets('errorText replaces helperText', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexDatePickerField(
          label: 'Start',
          helperText: 'never shown',
          errorText: 'required',
        ),
      ),
    );
    expect(find.text('required'), findsOneWidget);
    expect(find.text('never shown'), findsNothing);
  });

  testWidgets('isLoading swaps the trailing icon for a spinner',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexDatePickerField(label: 'Start', isLoading: true),
      ),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byIcon(Icons.calendar_today_outlined), findsNothing);
  });

  testWidgets('opens the picker on tap and forwards onChanged',
      (tester) async {
    DateTime? picked;
    await tester.pumpWidget(
      _harness(
        SoliplexDatePickerField(
          label: 'Start',
          initialValue: DateTime(2026, 5, 26),
          onChanged: (d) => picked = d,
        ),
      ),
    );
    await tester.tap(find.byType(TextFormField));
    await tester.pumpAndSettle();
    // showDatePicker opens a Dialog — confirm it landed.
    expect(find.byType(Dialog), findsOneWidget);
    // Confirm via OK to commit the initial selection.
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(picked, isNotNull);
  });
}
