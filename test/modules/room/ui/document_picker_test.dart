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
  });
}
