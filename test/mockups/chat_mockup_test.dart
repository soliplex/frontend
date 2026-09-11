import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/mockups/chat/chat_mockup.dart';
import 'package:soliplex_frontend/src/mockups/mockup.dart';
import 'package:soliplex_frontend/src/mockups/mockup_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the chat mockup opens on a conversation and replies to a send',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chat = Mockup(name: 'Chat', build: (_) => const ChatMockup());
    await tester.pumpWidget(MockupApp(mockups: [chat], initial: chat));
    await tester.pumpAndSettle();

    // The sidebar lists the room's threads; the timeline shows history.
    expect(find.text('Retrieval paper summary'), findsWidgets);
    expect(find.textContaining('hard negatives'), findsWidgets);

    await tester.enterText(find.byType(TextField).first, 'Hello there');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    // The scripted reply streams word by word; let it finish.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining('You said:'), findsOneWidget);
    expect(find.textContaining('Hello there'), findsWidgets);
  });

  testWidgets(
      'narrow: the panel opens as a sheet from the composer and keeps '
      'its state across dismissal', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chat = Mockup(name: 'Chat', build: (_) => const ChatMockup());
    await tester.pumpWidget(MockupApp(mockups: [chat], initial: chat));
    await tester.pumpAndSettle();

    // No floating panel on the narrow layout, only the composer's button.
    expect(find.byTooltip('Collapse'), findsNothing);
    expect(find.byTooltip('Open thread panel'), findsNothing);
    await tester.tap(find.byTooltip('Thread panel'));
    await tester.pumpAndSettle();
    expect(find.text('Databases'), findsOneWidget);

    // Open Skills, switch to Workspace, then dismiss the sheet.
    await tester.tap(find.text('Skills'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Workspace'));
    await tester.pumpAndSettle();
    // The barrier belongs to the mockup's own navigator, below the
    // harness toolbar; tap the room header, which the sheet leaves clear.
    await tester.tapAt(const Offset(200, 64));
    await tester.pumpAndSettle();
    expect(find.text('Databases'), findsNothing);

    await tester.tap(find.byTooltip('Thread panel'));
    await tester.pumpAndSettle();
    // Reopens on the Workspace tab; Skills is still open behind it.
    expect(find.text('Send'), findsOneWidget);
    await tester.tap(find.text('Context'));
    await tester.pumpAndSettle();
    expect(find.text('Auto-load basic skills'), findsOneWidget);
  });

  testWidgets('the + menu carries attach and the stubbed filter',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final chat = Mockup(name: 'Chat', build: (_) => const ChatMockup());
    await tester.pumpWidget(MockupApp(mockups: [chat], initial: chat));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Add image'), findsNothing);
    expect(find.byTooltip('Filter documents'), findsNothing);
    await tester.tap(find.byTooltip('Add to message'));
    await tester.pumpAndSettle();
    expect(find.text('Attach files or images…'), findsOneWidget);
    await tester.tap(find.text('Filter documents'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Document filtering — stubbed'), findsOneWidget);
  });
}
