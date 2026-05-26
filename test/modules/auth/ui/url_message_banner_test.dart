import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_frontend/src/modules/auth/connect_flow.dart';
import 'package:soliplex_frontend/src/modules/auth/ui/home_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: child),
    );

void main() {
  group('UrlMessageBanner', () {
    testWidgets('ConnectError shows text, error icon, and error container',
        (tester) async {
      late ThemeData theme;

      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              theme = Theme.of(context);
              return UrlMessageBanner(message: const ConnectError('Boom'));
            },
          ),
        ),
      );

      expect(find.text('Boom'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      final container = tester.widget<Container>(find.byType(Container).first);
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, equals(theme.colorScheme.errorContainer));
    });

    testWidgets('ConnectNotice shows text, no icon, no error container',
        (tester) async {
      await tester.pumpWidget(
        _wrap(UrlMessageBanner(message: const ConnectNotice('Heads up'))),
      );

      expect(find.text('Heads up'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
      expect(find.byType(Container), findsNothing);
    });
  });
}
