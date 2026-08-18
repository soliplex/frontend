import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
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

Widget _wrap(Widget child, {ThemeData? theme, double? width}) => MaterialApp(
      theme: theme ?? _configured(),
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            // A column, as the chat stacks it: free to span the width it is
            // given, free to collapse to nothing.
            child: Column(mainAxisSize: MainAxisSize.min, children: [child]),
          ),
        ),
      ),
    );

ThemeData _withLabel(String label) => ThemeData(
      extensions: [
        ClassificationTheme(
          defaultId: 'x',
          levels: [
            ClassificationLevel(
              id: 'x',
              label: label,
              background: const Color(0xFFEEDDDD),
              foreground: const Color(0xFF441111),
            ),
          ],
        ),
      ],
    );

void main() {
  group('ChatClassificationBand', () {
    testWidgets('shows the deployment default marking', (tester) async {
      await tester.pumpWidget(_wrap(const ChatClassificationBand()));
      expect(find.text('RESTRICTED'), findsOneWidget);
    });

    testWidgets('collapses whole when no marking is configured',
        (tester) async {
      await tester.pumpWidget(
        _wrap(const ChatClassificationBand(), theme: ThemeData()),
      );
      expect(tester.getSize(find.byType(ChatClassificationBand)), Size.zero);
    });

    // The band replaces its label's semantics with a named announcement, so a
    // regression here is silence for a screen reader — invisible on screen and
    // not recoverable from the label, which ExcludeSemantics drops.
    testWidgets('announces the marking to a screen reader', (tester) async {
      await tester.pumpWidget(_wrap(const ChatClassificationBand()));
      expect(
        find.bySemanticsLabel('Classification: RESTRICTED'),
        findsOneWidget,
      );
    });

    // A marking's colors are its own, never the app palette's: a brand
    // restyling must not be able to change how a marking reads.
    testWidgets('paints the level own colors, not the color scheme',
        (tester) async {
      await tester.pumpWidget(_wrap(const ChatClassificationBand()));

      final band = tester.widget<ColoredBox>(
        find.descendant(
          of: find.byType(ChatClassificationBand),
          matching: find.byType(ColoredBox),
        ),
      );
      expect(band.color, const Color(0xFFEEDDDD));
      expect(
        tester.widget<Text>(find.text('RESTRICTED')).style?.color,
        const Color(0xFF441111),
      );
    });

    // Clipping a marking is an integrity bug — a truncated label reads as a
    // different, lower marking than the one the room carries. The band has no
    // maxLines for that reason, unlike the room title above it.
    testWidgets('wraps a label too long for its width instead of truncating',
        (tester) async {
      const long = 'CONTROLLED UNCLASSIFIED INFORMATION';

      await tester.pumpWidget(
        _wrap(
          const ChatClassificationBand(),
          width: 120,
          theme: _withLabel('X'),
        ),
      );
      final oneLine =
          tester.getSize(find.byType(ChatClassificationBand)).height;

      await tester.pumpWidget(
        _wrap(
          const ChatClassificationBand(),
          width: 120,
          theme: _withLabel(long),
        ),
      );
      // Markings do not cross-fade: ClassificationTheme.lerp holds the
      // outgoing value for the theme transition, so the new label is only on
      // screen once that animation has run out.
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // Not clamped to a line count: `didExceedMaxLines` is the paragraph's
      // own report that it was cut off, and it carries no pixel constant, so
      // it survives type changes a height assertion would not.
      expect(
        tester.renderObject<RenderParagraph>(find.text(long)).didExceedMaxLines,
        isFalse,
      );
      // And it wrapped rather than running off the edge.
      expect(
        tester.getSize(find.byType(ChatClassificationBand)).height,
        greaterThan(oneLine),
      );
    });
  });

  group('ChatClassificationNotice', () {
    testWidgets('names the level the room carries', (tester) async {
      await tester.pumpWidget(_wrap(const ChatClassificationNotice()));
      expect(
        find.text('Information level is: RESTRICTED'),
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
