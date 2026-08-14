import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chat_classification.dart';

ThemeData _configured() => ThemeData(
      extensions: [
        ClassificationTheme(
          defaultId: 'restricted',
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
      ],
    );

Widget _wrap(Widget child, {ThemeData? theme}) => MaterialApp(
      theme: theme ?? _configured(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('ChatClassificationBadge', () {
    testWidgets('shows the deployment default marking', (tester) async {
      await tester.pumpWidget(_wrap(const ChatClassificationBadge()));
      expect(find.text('RESTRICTED'), findsOneWidget);
    });

    testWidgets('stands as tall as the bar buttons beside it', (tester) async {
      await tester.pumpWidget(_wrap(const ChatClassificationBadge()));
      expect(
        tester.getSize(find.byType(SoliplexClassificationBadge)).height,
        kMinInteractiveDimension,
      );
    });

    testWidgets(
        'collapses whole — gap included — when no marking is '
        'configured', (tester) async {
      await tester.pumpWidget(
        _wrap(const ChatClassificationBadge(), theme: ThemeData()),
      );
      expect(
        tester.getSize(find.byType(ChatClassificationBadge)),
        Size.zero,
      );
    });
  });

  group('ChatClassificationNotice', () {
    testWidgets('names the level the room carries', (tester) async {
      await tester.pumpWidget(_wrap(const ChatClassificationNotice()));
      expect(
        find.text('Information level is RESTRICTED for this room'),
        findsOneWidget,
      );
    });

    testWidgets('says nothing when no marking is configured', (tester) async {
      await tester.pumpWidget(
        _wrap(const ChatClassificationNotice(), theme: ThemeData()),
      );
      expect(find.textContaining('Information level'), findsNothing);
      expect(
        tester.getSize(find.byType(ChatClassificationNotice)),
        Size.zero,
      );
    });
  });
}
