import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;

import 'package:soliplex_frontend/src/modules/room/ui/chat_input.dart';

void main() {
  testWidgets('send button dispatches text and clears field', (tester) async {
    String? sentText;
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (text) => sentText = text,
            onCancel: () {},
            sessionState: sessionState,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Hello agent');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentText, 'Hello agent');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    sessionState.dispose();
  });

  testWidgets('send button disabled when text is empty', (tester) async {
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (_) {},
            onCancel: () {},
            sessionState: sessionState,
          ),
        ),
      ),
    );

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send),
    );
    expect(sendButton.onPressed, isNull);

    sessionState.dispose();
  });

  testWidgets('shows cancel button when session is running', (tester) async {
    bool cancelCalled = false;
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (_) {},
            onCancel: () => cancelCalled = true,
            sessionState: sessionState,
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.send), findsNothing);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    expect(cancelCalled, isTrue);

    sessionState.dispose();
  });

  testWidgets('text field readOnly during active run', (tester) async {
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (_) {},
            onCancel: () {},
            sessionState: sessionState,
          ),
        ),
      ),
    );

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);

    sessionState.dispose();
  });

  testWidgets('Enter key sends message', (tester) async {
    String? sentText;
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (text) => sentText = text,
            onCancel: () {},
            sessionState: sessionState,
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sentText, 'Hello');

    sessionState.dispose();
  });

  testWidgets('Enter key does not send during active run', (tester) async {
    String? sentText;
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (text) => sentText = text,
            onCancel: () {},
            sessionState: sessionState,
          ),
        ),
      ),
    );

    // Enter text via controller since TextField is readOnly during active run.
    tester.widget<TextField>(find.byType(TextField)).controller!.text =
        'Draft message';
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sentText, isNull);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Draft message',
    );

    sessionState.dispose();
  });

  testWidgets('chip deletion disabled during active run', (tester) async {
    const doc = RagDocument(id: '1', title: 'Report.pdf');
    RagDocument? removed;
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (_) {},
            onCancel: () {},
            sessionState: sessionState,
            selectedDocuments: {doc},
            onDocumentRemoved: (d) => removed = d,
          ),
        ),
      ),
    );

    // onDeleted is null, which removes the delete icon entirely.
    final chip = tester.widget<Chip>(find.byType(Chip));
    expect(chip.onDeleted, isNull);
    expect(find.byIcon(Icons.close), findsNothing);
    expect(removed, isNull);

    sessionState.dispose();
  });

  testWidgets('filter button disabled during active run', (tester) async {
    bool filterTapped = false;
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChatInput(
            onSend: (_) {},
            onCancel: () {},
            sessionState: sessionState,
            onFilterTap: () => filterTapped = true,
          ),
        ),
      ),
    );

    final button = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.filter_alt),
    );
    expect(button.onPressed, isNull);
    expect(filterTapped, isFalse);

    sessionState.dispose();
  });

  testWidgets('filter button hidden when onFilterTap is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ChatInput(onSend: (_) {}, onCancel: () {})),
      ),
    );

    expect(find.byIcon(Icons.filter_alt), findsNothing);
  });

  group('document chips', () {
    testWidgets('displays selected document chips', (tester) async {
      final docs = {const RagDocument(id: '1', title: 'Report.pdf')};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              selectedDocuments: docs,
            ),
          ),
        ),
      );

      expect(find.text('Report.pdf'), findsOneWidget);
    });

    testWidgets('shows filter button when onFilterTap provided', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              onFilterTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
    });

    testWidgets('calls onDocumentRemoved when chip deleted', (tester) async {
      const doc = RagDocument(id: '1', title: 'Report.pdf');
      RagDocument? removed;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              selectedDocuments: {doc},
              onDocumentRemoved: (d) => removed = d,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close).first);
      expect(removed, doc);
    });
  });

  group('attach file button', () {
    testWidgets('shows when onAttachFile provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              onAttachFile: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
    });

    testWidgets('hidden when onAttachFile is null', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ChatInput(onSend: (_) {}, onCancel: () {})),
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('disabled during active run', (tester) async {
      bool attachCalled = false;
      final sessionState = signal<AgentSessionState?>(
        AgentSessionState.running,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              sessionState: sessionState,
              onAttachFile: () => attachCalled = true,
            ),
          ),
        ),
      );

      final button = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.attach_file),
      );
      expect(button.onPressed, isNull);
      expect(attachCalled, isFalse);

      sessionState.dispose();
    });

    testWidgets('calls onAttachFile when tapped', (tester) async {
      bool attachCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              onAttachFile: () => attachCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.attach_file));
      expect(attachCalled, isTrue);
    });
  });
}
