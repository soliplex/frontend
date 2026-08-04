import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_info/documents_card.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: child)),
      );

  const docA = RagDocument(
    id: 'id-a',
    title: 'Alpha Doc',
    uri: '/files/alpha.pdf',
  );
  const docB = RagDocument(
    id: 'id-b',
    title: 'Beta Doc',
    uri: '/files/beta.pdf',
  );
  const docC = RagDocument(
    id: 'id-c',
    title: 'Gamma Doc',
    uri: '/files/gamma.pdf',
  );

  group('loading and error', () {
    testWidgets('shows loading spinner while future pending', (tester) async {
      final completer = Completer<List<RagDocument>>();
      await tester.pumpWidget(wrap(
        DocumentsCard(documentsFuture: completer.future, onRetry: () {}),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows error with retry button when future fails',
        (tester) async {
      final completer = Completer<List<RagDocument>>();
      await tester.pumpWidget(wrap(
        DocumentsCard(documentsFuture: completer.future, onRetry: () {}),
      ));

      completer.completeError(Exception('network error'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load documents'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('retry button re-triggers onRetry callback', (tester) async {
      var retryCalled = false;
      final completer = Completer<List<RagDocument>>();
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: completer.future,
          onRetry: () => retryCalled = true,
        ),
      ));

      completer.completeError(Exception('fail'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Retry'));
      expect(retryCalled, isTrue);
    });

    testWidgets('shows "No documents" when list is empty', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const []),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('No documents in this room.'), findsOneWidget);
      expect(find.text('DOCUMENTS (0)'), findsOneWidget);
    });
  });

  // A PDF and a file embedded in it, which the backend ingests as its own
  // document and relates to its container only through an `#attachment=`
  // marker in its URI.
  const container = RagDocument(
    id: 'id-container',
    title: null,
    uri: 'file:///docs/annual-report.pdf',
  );
  const attachment = RagDocument(
    id: 'id-attachment',
    title: null,
    uri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
  );

  group('embedded files', () {
    testWidgets('an embedded file names the document it came from',
        (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [container, attachment]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('budget.xlsx'), findsOneWidget);
      // Both rows are on screen, so exactly one provenance line means a
      // container states none of its own.
      expect(find.text('annual-report.pdf'), findsOneWidget);
      expect(find.text('in annual-report.pdf'), findsOneWidget);
    });
  });

  group('document title', () {
    testWidgets('an expanded document shows its title', (tester) async {
      const titled = RagDocument(
        id: 'id-titled',
        title: 'Annual Operations Review',
        uri: 'file:///docs/report.pdf',
      );
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [titled]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('report.pdf'));
      await tester.pump();

      expect(find.textContaining('Annual Operations Review'), findsOneWidget);
    });

    testWidgets('an expanded document whose label is the title shows it once',
        (tester) async {
      // The row label falls back to the title when the uri names no file.
      // Repeating it under a `title` lead-in would print the same string twice.
      const titleAsLabel = RagDocument(
        id: 'id-title-as-label',
        title: 'Annual Operations Review',
        uri: 'file:///docs/',
      );
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [titleAsLabel]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annual Operations Review'));
      await tester.pump();

      expect(find.textContaining('Annual Operations Review'), findsOneWidget);
    });

    testWidgets('an expanded document with no title shows no title row',
        (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [container]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('annual-report.pdf'));
      await tester.pump();

      // The label goes with the value — a lone `title` lead-in announces
      // nothing.
      expect(find.text('id'), findsOneWidget);
      expect(find.textContaining('title  '), findsNothing);
    });
  });

  group('document list', () {
    testWidgets('shows document list with names', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA, docB]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('alpha.pdf'), findsOneWidget);
      expect(find.text('beta.pdf'), findsOneWidget);
    });

    testWidgets('search bar appears when more than 1 document', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA, docB]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('search bar hidden when only 1 document', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('typing in search updates displayed list', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA, docB, docC]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();

      expect(find.text('alpha.pdf'), findsOneWidget);
      expect(find.text('beta.pdf'), findsNothing);
      expect(find.text('gamma.pdf'), findsNothing);
    });

    testWidgets('search shows "N / total" count in header', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA, docB, docC]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();

      expect(find.text('DOCUMENTS (1 / 3)'), findsOneWidget);
    });

    testWidgets('zero search results shows appropriate state', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA, docB]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzznomatch');
      await tester.pump();

      expect(find.text('alpha.pdf'), findsNothing);
      expect(find.text('beta.pdf'), findsNothing);
      expect(find.text('DOCUMENTS (0 / 2)'), findsOneWidget);
    });

    testWidgets('clear search button resets to full list', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA, docB, docC]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'alpha');
      await tester.pump();
      expect(find.text('beta.pdf'), findsNothing);

      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();

      expect(find.text('alpha.pdf'), findsOneWidget);
      expect(find.text('beta.pdf'), findsOneWidget);
      expect(find.text('gamma.pdf'), findsOneWidget);
      expect(find.text('DOCUMENTS (3)'), findsOneWidget);
    });
  });

  group('document expansion', () {
    testWidgets('tapping document expands metadata', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('id'), findsNothing);

      await tester.tap(find.text('alpha.pdf'));
      await tester.pump();

      expect(find.text('id'), findsOneWidget);
    });

    testWidgets('tapping expanded document collapses it', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha.pdf'));
      await tester.pump();
      expect(find.text('id'), findsOneWidget);

      await tester.tap(find.text('alpha.pdf'));
      await tester.pump();
      expect(find.text('id'), findsNothing);
    });

    testWidgets('metadata shows document ID and the document uri as the source',
        (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docA]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('alpha.pdf'));
      await tester.pump();

      expect(find.text('id-a'), findsOneWidget);
      // With no source_url, the document uri is shown (non-clickable) as the
      // document's source.
      expect(find.text('/files/alpha.pdf'), findsOneWidget);
    });

    testWidgets('metadata shows timestamps when present', (tester) async {
      final docWithDates = RagDocument(
        id: 'id-dated',
        title: 'Dated Doc',
        uri: '/files/dated.txt',
        createdAt: DateTime(2024, 3, 15, 10, 30),
        updatedAt: DateTime(2024, 6, 20, 14, 45),
      );

      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value([docWithDates]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('dated.txt'));
      await tester.pump();

      expect(find.text('created_at'), findsOneWidget);
      expect(find.text('updated_at'), findsOneWidget);
      expect(find.text('2024-03-15 10:30'), findsOneWidget);
      expect(find.text('2024-06-20 14:45'), findsOneWidget);
    });

    // Regression for issue #338: backend timestamps are UTC instants, so the
    // rendered date+time must be the viewer's local clock, not raw UTC fields.
    // Caveat: only fails on a runner whose zone differs from UTC.
    testWidgets('renders a UTC timestamp in the viewer local zone',
        (tester) async {
      final utcCreated = DateTime.utc(2024, 3, 15, 2, 30);
      final local = utcCreated.toLocal();
      final expected = '${local.year}-${local.month.toString().padLeft(2, '0')}'
          '-${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:'
          '${local.minute.toString().padLeft(2, '0')}';

      final doc = RagDocument(
        id: 'id-utc',
        title: 'UTC Doc',
        uri: '/files/utc.txt',
        createdAt: utcCreated,
      );

      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value([doc]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('utc.txt'));
      await tester.pump();

      expect(find.text(expected), findsOneWidget);
    });
  });

  group('metadata dialog', () {
    const docWithMeta = RagDocument(
      id: 'id-meta',
      title: 'Meta Doc',
      uri: '/files/meta.pdf',
      metadata: {'author': 'Alice', 'pages': 42},
    );

    const docNoMeta = RagDocument(
      id: 'id-nometa',
      title: 'No Meta Doc',
      uri: '/files/nometa.pdf',
    );

    testWidgets('"Show metadata" button appears when metadata non-empty',
        (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docWithMeta]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('meta.pdf'));
      await tester.pump();

      expect(find.text('Show metadata'), findsOneWidget);
    });

    testWidgets('"Show metadata" button hidden when metadata empty',
        (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docNoMeta]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('nometa.pdf'));
      await tester.pump();

      expect(find.text('Show metadata'), findsNothing);
    });

    testWidgets('dialog displays metadata entries', (tester) async {
      await tester.pumpWidget(wrap(
        DocumentsCard(
          documentsFuture: Future.value(const [docWithMeta]),
          onRetry: () {},
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('meta.pdf'));
      await tester.pump();

      await tester.tap(find.text('Show metadata'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('author'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('pages'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
    });
  });
}
