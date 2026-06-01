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
  testWidgets('forwards onChanged to the underlying field', (tester) async {
    String? captured;
    await tester.pumpWidget(
      _harness(SoliplexInput(label: 'Name', onChanged: (v) => captured = v)),
    );
    await tester.enterText(find.byType(TextFormField), 'hello');
    expect(captured, 'hello');
  });

  group('password mode', () {
    testWidgets('obscures text by default', (tester) async {
      await tester.pumpWidget(
        _harness(const SoliplexInput(label: 'Password', isPassword: true)),
      );
      final editable = tester.widget<EditableText>(find.byType(EditableText));
      expect(editable.obscureText, isTrue);
    });

    testWidgets('eye toggle reveals and re-obscures', (tester) async {
      await tester.pumpWidget(
        _harness(const SoliplexInput(label: 'Password', isPassword: true)),
      );
      expect(find.byIcon(Icons.visibility), findsOneWidget);
      await tester.tap(find.byIcon(Icons.visibility));
      await tester.pump();
      expect(find.byIcon(Icons.visibility_off), findsOneWidget);
      // Toggle back.
      await tester.tap(find.byIcon(Icons.visibility_off));
      await tester.pump();
      expect(find.byIcon(Icons.visibility), findsOneWidget);
    });
  });

  testWidgets('isLoading disables interaction and shows a spinner', (
    tester,
  ) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _harness(
        SoliplexInput(
          label: 'Username',
          controller: controller,
          isLoading: true,
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'hi');
    expect(controller.text, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final spinner = tester.getSize(find.byType(CircularProgressIndicator));
    expect(spinner.width, spinner.height, reason: 'spinner must stay round');
  });

  testWidgets('enabled: false disables without spinner', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _harness(
        SoliplexInput(
          label: 'Locked',
          controller: controller,
          enabled: false,
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'hi');
    expect(controller.text, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('readOnly blocks edits while staying enabled', (tester) async {
    final controller = TextEditingController();
    await tester.pumpWidget(
      _harness(
        SoliplexInput(
          label: 'Frozen',
          controller: controller,
          readOnly: true,
        ),
      ),
    );
    await tester.enterText(find.byType(TextFormField), 'hi');
    expect(controller.text, isEmpty, reason: 'readOnly must reject edits');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isTrue, reason: 'readOnly keeps the field enabled');
  });

  testWidgets('forwards an external focusNode to the field', (tester) async {
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);
    await tester.pumpWidget(
      _harness(SoliplexInput(label: 'Name', focusNode: focusNode)),
    );
    expect(focusNode.hasFocus, isFalse);
    focusNode.requestFocus();
    await tester.pump();
    expect(focusNode.hasFocus, isTrue);
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode, same(focusNode));
  });
}
