import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/shared/marking/effective_marking.dart';
import 'package:soliplex_frontend/src/shared/marking/marking_app_chrome.dart';
import 'package:soliplex_frontend/src/shared/marking/pre_access_notice.dart';

Widget _app({
  required List<Override> overrides,
  Widget child = const Scaffold(body: Text('PROTECTED')),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: soliplexLightTheme(),
      home: MarkingAppChrome(child: child),
    ),
  );
}

void main() {
  group('effective marking providers', () {
    test('default everywhere is CUI', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(effectiveMarkingProvider), DatasetMarking.cui);
      expect(
        container.read(datasetMarkingProvider('any-id')),
        DatasetMarking.cui,
      );
    });
  });

  group('MarkingAppChrome', () {
    testWidgets('gates protected content behind the pre-access notice',
        (tester) async {
      await tester.pumpWidget(_app(overrides: const []));

      expect(find.text('PROTECTED'), findsNothing);
      expect(find.byType(PreAccessNotice), findsOneWidget);
    });

    testWidgets('acknowledging reveals content and the marking banner',
        (tester) async {
      await tester.pumpWidget(_app(overrides: const []));

      await tester.ensureVisible(find.text('I ACKNOWLEDGE'));
      await tester.tap(find.text('I ACKNOWLEDGE'));
      await tester.pumpAndSettle();

      expect(find.text('PROTECTED'), findsOneWidget);
      expect(find.byType(SoliplexMarkingBanner), findsOneWidget);
    });

    testWidgets('classified contexts also show a bottom footer banner',
        (tester) async {
      await tester.pumpWidget(
        _app(
          overrides: [
            effectiveMarkingProvider.overrideWithValue(DatasetMarking.secret),
            markingNoticeAcknowledgedProvider
                .overrideWithValue(Signal<bool>(true)),
          ],
        ),
      );
      await tester.pump();

      // Top banner + bottom footer.
      expect(find.byType(SoliplexMarkingBanner), findsNWidgets(2));
    });
  });
}
