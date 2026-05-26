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

  testWidgets('renders label, hint, and helper', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexInput(
          label: 'Email',
          hintText: 'you@example.com',
          helperText: 'never shared',
        ),
      ),
    );
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('you@example.com'), findsOneWidget);
    expect(find.text('never shared'), findsOneWidget);
  });

  testWidgets('errorText replaces helperText', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexInput(
          label: 'Email',
          helperText: 'never shared',
          errorText: 'bad email',
        ),
      ),
    );
    expect(find.text('bad email'), findsOneWidget);
    expect(find.text('never shared'), findsNothing);
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

  group('loading mode', () {
    testWidgets('disables interaction and shows a spinner', (tester) async {
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
    });
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

  testWidgets('passes validator through to the form field', (tester) async {
    final key = GlobalKey<FormState>();
    await tester.pumpWidget(
      _harness(
        Form(
          key: key,
          child: SoliplexInput(
            label: 'Email',
            validator: (v) => v == null || v.isEmpty ? 'required' : null,
          ),
        ),
      ),
    );
    expect(key.currentState!.validate(), isFalse);
    await tester.pump();
    expect(find.text('required'), findsOneWidget);
  });
}
