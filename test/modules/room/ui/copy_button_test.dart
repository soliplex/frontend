import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/copy_button.dart';

void main() {
  testWidgets('shows copy icon initially', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyButton(text: 'hello')),
      ),
    );

    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);
  });

  testWidgets('swaps to check icon after tap then reverts', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyButton(text: 'hello')),
      ),
    );

    await tester.tap(find.byType(CopyButton));
    await tester.pump();

    expect(find.byIcon(Icons.check), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);

    // After 2 seconds, reverts to copy icon
    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('copies text to clipboard', (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map;
        copiedText = args['text'] as String?;
      }
      return null;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyButton(text: 'hello world')),
      ),
    );

    await tester.tap(find.byType(CopyButton));
    await tester.pump();

    expect(copiedText, 'hello world');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets('shows error icon when clipboard fails then reverts',
      (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'ERROR', message: 'clipboard failed');
      }
      return null;
    });

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyButton(text: 'hello')),
      ),
    );

    await tester.tap(find.byType(CopyButton));
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsNothing);

    await tester.pump(const Duration(seconds: 2));

    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsNothing);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
}
