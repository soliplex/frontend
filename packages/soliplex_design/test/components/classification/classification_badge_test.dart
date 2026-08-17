import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

ThemeData _configuredTheme() => soliplexLightTheme(
      classifications: ClassificationTheme(
        defaultId: 'public',
        levels: const [
          ClassificationLevel(
            id: 'public',
            label: 'PUBLIC',
            background: Color(0xFFDDEEDD),
            foreground: Color(0xFF114411),
          ),
          ClassificationLevel(
            id: 'restricted',
            label: 'RESTRICTED',
            background: Color(0xFFEEDDDD),
            foreground: Color(0xFF441111),
            icon: Icons.lock,
          ),
        ],
      ),
    );

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? _configuredTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders the resolved label and icon', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(classification: 'restricted')),
    );
    expect(find.text('RESTRICTED'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsOneWidget);
  });

  testWidgets('null resolves to the configured default', (tester) async {
    await tester.pumpWidget(_wrap(const SoliplexClassificationBadge()));
    expect(find.text('PUBLIC'), findsOneWidget);
  });

  testWidgets('exposes a Semantics classification label', (tester) async {
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(classification: 'restricted')),
    );
    expect(find.bySemanticsLabel('Classification: RESTRICTED'), findsOneWidget);
  });

  testWidgets('unknown id renders a fail-loud label carrying the id',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(classification: 'bogus')),
    );
    expect(find.textContaining('bogus'), findsOneWidget);
  });

  testWidgets('renders nothing for the unconfigured built-in fallback',
      (tester) async {
    // Bare Material theme → ClassificationTheme.of falls back; the default
    // resolves to the neutral built-in, which is suppressed.
    await tester.pumpWidget(
      _wrap(const SoliplexClassificationBadge(), theme: ThemeData()),
    );
    expect(find.text('UNMARKED'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Classification')), findsNothing);
  });
}
