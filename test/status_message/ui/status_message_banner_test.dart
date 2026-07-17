import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/status_message/status_message.dart';
import 'package:soliplex_frontend/src/status_message/status_message_dismissals.dart';
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
      StatusMessageBanner.withFetcher(
        fetcher: () async => _upcoming(),
        serverLabel: 'production-east',
      ),
    ));
    await tester.pump();

    // Collapsed: title, countdown, one-line body, Details; no window range and
    // no server label (that is expanded-only).
    expect(find.text('Scheduled maintenance'), findsOneWidget);
    expect(find.textContaining('STARTS IN'), findsOneWidget);
    expect(find.text('Save your work.'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.textContaining('·'), findsNothing);
    expect(find.text('production-east'), findsNothing);

    await tester.tap(find.text('Details'));
    await tester.pump();

    // Expanded: the window range line and server label appear, Show less
    // replaces Details.
    expect(find.textContaining('·'), findsOneWidget);
    expect(find.text('production-east'), findsOneWidget);
    expect(find.text('Show less'), findsOneWidget);
    expect(find.text('Details'), findsNothing);
  });

  testWidgets('dismiss hides the banner and survives a remount',
      (tester) async {
    final store = StatusMessageDismissals();
    final msg = _upcoming();
    Widget scoped(Key key) => ProviderScope(
          overrides: [
            statusMessageDismissalsProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme:
                lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
            home: Scaffold(
              body: StatusMessageBanner.withFetcher(
                key: key,
                fetcher: () async => msg,
              ),
            ),
          ),
        );

    await tester.pumpWidget(scoped(const ValueKey('a')));
    await tester.pump();
    expect(find.text('Scheduled maintenance'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text('Scheduled maintenance'), findsNothing);

    // Remount a fresh banner for the same message — still dismissed.
    await tester.pumpWidget(scoped(const ValueKey('b')));
    await tester.pump();
    expect(find.text('Scheduled maintenance'), findsNothing);
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
