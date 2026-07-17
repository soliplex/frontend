import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/status_message/status_message.dart';
import 'package:soliplex_frontend/src/status_message/ui/status_message_banner.dart';

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
        home: Scaffold(body: child),
      ),
    );

StatusMessage _upcoming() => StatusMessage(
      id: 'm',
      title: 'Scheduled maintenance',
      body: 'Save your work.',
      intent: MessageIntent.warning,
      category: MessageCategory.maintenance,
      window: MessageWindow(
        start: DateTime.now().toUtc().add(const Duration(hours: 3)),
        end: DateTime.now().toUtc().add(const Duration(hours: 5)),
      ),
    );

void main() {
  testWidgets('collapsed by default, expands via Details', (tester) async {
    await tester.pumpWidget(_wrap(
      StatusMessageBanner.withFetcher(fetcher: () async => _upcoming()),
    ));
    await tester.pump();

    // Collapsed: title, countdown, one-line body, Details; no window range.
    expect(find.text('Scheduled maintenance'), findsOneWidget);
    expect(find.textContaining('STARTS IN'), findsOneWidget);
    expect(find.text('Save your work.'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);

    await tester.tap(find.text('Details'));
    await tester.pump();

    // Expanded: the window range line appears, Show less replaces Details.
    expect(find.textContaining('·'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
  });

  testWidgets('windowless message shows no pill and no window range',
      (tester) async {
    final windowless = StatusMessage(
      id: 'n',
      title: 'Heads up',
      body: 'A general notice.',
      intent: MessageIntent.info,
      category: MessageCategory.general,
    );
    await tester.pumpWidget(_wrap(
      StatusMessageBanner.withFetcher(fetcher: () async => windowless),
    ));
    await tester.pump();

    expect(find.text('Heads up'), findsOneWidget);
    expect(find.byType(SoliplexBadge), findsNothing);
    await tester.tap(find.text('Details'));
    await tester.pump();
    expect(find.textContaining('·'), findsNothing);
    expect(find.text('A general notice.'), findsOneWidget);
  });
}
