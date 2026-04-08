import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/document_picker.dart';

final _docs = [
  const RagDocument(id: '1', title: 'Report.pdf', uri: '/files/Report.pdf'),
  const RagDocument(
    id: '2',
    title: 'Summary.docx',
    uri: '/files/Summary.docx',
  ),
  const RagDocument(id: '3', title: 'Data.xlsx', uri: '/files/Data.xlsx'),
];

void main() {
  group('DocumentPicker', () {
    testWidgets('displays all documents', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPicker(
              documents: _docs,
              selected: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Report.pdf'), findsOneWidget);
      expect(find.text('Summary.docx'), findsOneWidget);
      expect(find.text('Data.xlsx'), findsOneWidget);
    });

    testWidgets('calls onChanged when document tapped', (tester) async {
      Set<RagDocument>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPicker(
              documents: _docs,
              selected: const {},
              onChanged: (s) => result = s,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Report.pdf'));
      expect(result, {_docs[0]});
    });

    testWidgets('deselects already-selected document', (tester) async {
      Set<RagDocument>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPicker(
              documents: _docs,
              selected: {_docs[0]},
              onChanged: (s) => result = s,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Report.pdf'));
      expect(result, isEmpty);
    });

    testWidgets('clear all resets selection', (tester) async {
      Set<RagDocument>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPicker(
              documents: _docs,
              selected: {_docs[0], _docs[1]},
              onChanged: (s) => result = s,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Clear all'));
      expect(result, isEmpty);
    });

    testWidgets('search filters documents', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPicker(
              documents: _docs,
              selected: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), 'report');
      await tester.pump();

      expect(find.text('Report.pdf'), findsOneWidget);
      expect(find.text('Summary.docx'), findsNothing);
      expect(find.text('Data.xlsx'), findsNothing);
    });

    testWidgets('search matches URI', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentPicker(
              documents: _docs,
              selected: const {},
              onChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '/files/Data');
      await tester.pump();

      expect(find.text('Data.xlsx'), findsOneWidget);
      expect(find.text('Report.pdf'), findsNothing);
      expect(find.text('Summary.docx'), findsNothing);
    });
  });

  group('showDocumentPicker', () {
    testWidgets('shows loading then documents', (tester) async {
      final completer = Completer<List<RagDocument>>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDocumentPicker(
                context: context,
                fetchDocuments: () => completer.future,
                selected: const {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      // Loading state: spinner visible, Done disabled.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final doneButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(doneButton.onPressed, isNull);

      // Resolve the future.
      completer.complete(_docs);
      await tester.pumpAndSettle();

      // Documents visible, Done enabled.
      expect(find.text('Report.pdf'), findsOneWidget);
      final doneAfter = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(doneAfter.onPressed, isNotNull);
    });

    testWidgets('shows error with retry', (tester) async {
      int fetchCount = 0;
      final errorCompleter = Completer<List<RagDocument>>();

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDocumentPicker(
                context: context,
                fetchDocuments: () {
                  fetchCount++;
                  if (fetchCount == 1) return errorCompleter.future;
                  return Future.value(_docs);
                },
                selected: const {},
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pump();

      // Complete with error after FutureBuilder has subscribed.
      errorCompleter.completeError(Exception('network'));
      await tester.pumpAndSettle();

      expect(find.text('Failed to load documents.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      final doneButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Done'),
      );
      expect(doneButton.onPressed, isNull);

      // Tap retry — second fetch succeeds.
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Report.pdf'), findsOneWidget);
      expect(fetchCount, 2);
    });

    testWidgets('Done returns selected documents', (tester) async {
      Set<RagDocument>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDocumentPicker(
                  context: context,
                  fetchDocuments: () => Future.value(_docs),
                  selected: const {},
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      // Select two documents.
      await tester.tap(find.text('Report.pdf'));
      await tester.pump();
      await tester.tap(find.text('Data.xlsx'));
      await tester.pump();

      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      expect(result, {_docs[0], _docs[2]});
    });

    testWidgets('cancel returns null', (tester) async {
      Set<RagDocument>? result;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await showDocumentPicker(
                  context: context,
                  fetchDocuments: () => Future.value(_docs),
                  selected: const {},
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(result, isNull);
    });
  });
}
