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

void main() {
  final upcoming = StatusMessage(
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

  testWidgets('renders an upcoming maintenance banner, then minimizes',
      (tester) async {
    await tester.pumpWidget(_wrap(
      StatusMessageBanner.withFetcher(fetcher: () async => upcoming),
    ));
    await tester.pump(); // resolve the fetch future

    expect(find.text('Scheduled maintenance'), findsOneWidget);
    expect(find.text('Save your work.'), findsOneWidget);
    expect(find.textContaining('BEGINS IN'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.expand_less));
    await tester.pump();

    expect(find.text('Save your work.'), findsNothing); // body hidden minimized
    expect(find.text('Scheduled maintenance'), findsOneWidget); // title stays
  });

  testWidgets('renders nothing when there is no message', (tester) async {
    await tester.pumpWidget(_wrap(
      StatusMessageBanner.withFetcher(fetcher: () async => null),
    ));
    await tester.pump();
    expect(find.byType(SoliplexBadge), findsNothing);
  });
}
