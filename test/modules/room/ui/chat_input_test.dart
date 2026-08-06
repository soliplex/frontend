import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_agent/soliplex_agent.dart' hide State;
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/attachable_images.dart';
import 'package:soliplex_frontend/src/modules/room/composer_draft.dart';
import 'package:soliplex_frontend/src/modules/room/pick_file.dart';
import 'package:soliplex_frontend/src/modules/room/pick_image.dart';
import 'package:soliplex_frontend/src/modules/room/ui/chat_input.dart';
import 'package:soliplex_frontend/src/modules/room/ui/inline_image_composer_controller.dart';
import 'package:soliplex_logging/soliplex_logging.dart';

import '../image_fixtures.dart';

void main() {
  group('composerAcceptsText', () {
    test('refuses while a run holds the composer read-only', () {
      // Typed characters are swallowed in these states, so text routed in from
      // elsewhere would be stuck there until the run ended.
      for (final state in [
        AgentSessionState.spawning,
        AgentSessionState.running,
      ]) {
        expect(
          composerAcceptsText(enabled: true, sessionState: state),
          isFalse,
          reason: '$state should hold the composer',
        );
      }
    });

    test('refuses while the screen has the composer disabled', () {
      // A thread still loading its messages, whatever the session is doing.
      for (final state in [null, AgentSessionState.completed]) {
        expect(
          composerAcceptsText(enabled: false, sessionState: state),
          isFalse,
          reason: 'disabled should refuse with session $state',
        );
      }
    });

    test('takes text with no session yet', () {
      // A room's first message, before anything has spawned.
      expect(
        composerAcceptsText(enabled: true, sessionState: null),
        isTrue,
      );
    });
  });

  testWidgets('send button dispatches text and clears field', (tester) async {
    List<MessagePart>? sentParts;
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ChatInput(
          onSend: (parts) => sentParts = parts,
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    // Padded on purpose: the composer sends one run of trimmed text, and
    // nothing downstream trims again.
    await tester.enterText(find.byType(TextField), '  Hello agent  ');
    await tester.pump();

    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sentParts, hasLength(1));
    expect((sentParts!.single as TextPart).text, 'Hello agent');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );

    sessionState.dispose();
  });

  testWidgets('long pasted text does not overflow the surrounding layout',
      (tester) async {
    // Mirrors the room layout: the chat input is a non-flex child of a
    // bounded Column alongside an Expanded body. An uncapped field grows
    // to its content height and overflows the Column.
    final controller = InlineImageComposerController()..text = 'line\n' * 500;
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: Column(
          children: [
            const Expanded(child: SizedBox.expand()),
            ChatInput(
              controller: controller,
              onSend: (_) {},
              onCancel: () {},
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('send button disabled when text is empty', (tester) async {
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ChatInput(
          onSend: (_) {},
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    final sendButton = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.send),
    );
    expect(sendButton.onPressed, isNull);

    sessionState.dispose();
  });

  testWidgets('refuses to send while an image could not be restored',
      (tester) async {
    // Sending would drop the placeholder and deliver a different message from
    // the one on screen, so the composer says why instead.
    final controller = InlineImageComposerController()
      ..restoreDraft('look at $composerDraftImageMarker');
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ChatInput(
          controller: controller,
          onSend: (_) {},
          onCancel: () {},
        ),
      ),
    ));

    expect(
      tester
          .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.send))
          .onPressed,
      isNull,
    );
    expect(find.text(unrestoredImageNotice), findsOneWidget);
  });

  testWidgets('shows cancel button when session is running', (tester) async {
    bool cancelCalled = false;
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ChatInput(
          onSend: (_) {},
          onCancel: () => cancelCalled = true,
          sessionState: sessionState,
        ),
      ),
    ));

    expect(find.byIcon(Icons.stop), findsOneWidget);
    expect(find.byIcon(Icons.send), findsNothing);

    await tester.tap(find.byIcon(Icons.stop));
    await tester.pump();
    expect(cancelCalled, isTrue);

    sessionState.dispose();
  });

  testWidgets('text field readOnly during active run', (tester) async {
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ChatInput(
          onSend: (_) {},
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

    final textField = tester.widget<TextField>(find.byType(TextField));
    expect(textField.readOnly, isTrue);

    sessionState.dispose();
  });

  testWidgets('Enter key sends message', (tester) async {
    String? sentText;
    final sessionState = signal<AgentSessionState?>(null);

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ChatInput(
          onSend: (parts) => sentText = parts.plainText,
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

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

    await tester.pumpWidget(MaterialApp(
      theme: soliplexLightTheme(),
      home: Scaffold(
        body: ChatInput(
          onSend: (parts) => sentText = parts.plainText,
          onCancel: () {},
          sessionState: sessionState,
        ),
      ),
    ));

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
        theme: soliplexLightTheme(),
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
    expect(find.byIcon(Icons.cancel), findsNothing);
    expect(removed, isNull);

    sessionState.dispose();
  });

  testWidgets('filter button disabled during active run', (tester) async {
    bool filterTapped = false;
    final sessionState = signal<AgentSessionState?>(AgentSessionState.running);

    await tester.pumpWidget(
      MaterialApp(
        theme: soliplexLightTheme(),
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
        theme: soliplexLightTheme(),
        home: Scaffold(
          body: ChatInput(
            onSend: (_) {},
            onCancel: () {},
          ),
        ),
      ),
    );

    expect(find.byIcon(Icons.filter_alt), findsNothing);
  });

  group('document chips', () {
    testWidgets('displays selected document chips', (tester) async {
      final docs = {
        const RagDocument(id: '1', title: 'Report.pdf'),
      };

      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
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

    testWidgets('shows filter button when onFilterTap provided',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
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
          theme: soliplexLightTheme(),
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

      // SoliplexChip uses Material's default delete glyph (Icons.cancel).
      await tester.tap(find.byIcon(Icons.cancel).first);
      expect(removed, doc);
    });

    testWidgets('an embedded file names its container on hover',
        (tester) async {
      // A chip shows the name alone, so two files embedded in different
      // documents under one name are otherwise indistinguishable here.
      const doc = RagDocument(
        id: '1',
        title: null,
        uri: 'file:///docs/annual-report.pdf#attachment=budget.xlsx',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              selectedDocuments: {doc},
            ),
          ),
        ),
      );

      expect(find.text('budget.xlsx'), findsOneWidget);
      expect(
        find.byTooltip('budget.xlsx embedded in annual-report.pdf'),
        findsOneWidget,
      );
    });
  });

  group('attach file button', () {
    testWidgets('shows when onAttachFile provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
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
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsNothing);
    });

    testWidgets('disabled during active run', (tester) async {
      bool attachCalled = false;
      final sessionState =
          signal<AgentSessionState?>(AgentSessionState.running);

      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
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
          theme: soliplexLightTheme(),
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

    testWidgets(
      'opens a popup menu with Files and Folder items when both callbacks '
      'are provided',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: soliplexLightTheme(),
            home: Scaffold(
              body: ChatInput(
                onSend: (_) {},
                onCancel: () {},
                onAttachFile: () {},
                onAttachFolder: () {},
              ),
            ),
          ),
        );

        // Menu items aren't in the tree until the trigger is tapped.
        expect(find.text('Files…'), findsNothing);
        expect(find.text('Folder…'), findsNothing);

        await tester.tap(find.byIcon(Icons.attach_file));
        await tester.pumpAndSettle();

        expect(find.text('Files…'), findsOneWidget);
        expect(find.text('Folder…'), findsOneWidget);
      },
    );

    testWidgets(
      'popup menu items invoke the matching callback',
      (tester) async {
        var fileTaps = 0;
        var folderTaps = 0;

        await tester.pumpWidget(
          MaterialApp(
            theme: soliplexLightTheme(),
            home: Scaffold(
              body: ChatInput(
                onSend: (_) {},
                onCancel: () {},
                onAttachFile: () => fileTaps++,
                onAttachFolder: () => folderTaps++,
              ),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.attach_file));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Files…'));
        await tester.pumpAndSettle();
        expect(fileTaps, 1);
        expect(folderTaps, 0);

        await tester.tap(find.byIcon(Icons.attach_file));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Folder…'));
        await tester.pumpAndSettle();
        expect(fileTaps, 1);
        expect(folderTaps, 1);
      },
    );
  });

  group('add image button', () {
    PickedImage pickedImage(
      String name,
      String mimeType, {
      Uint8List? bytes,
    }) =>
        PickedImage(
          name: name,
          mimeType: mimeType,
          bytes: bytes ?? onePixelPng,
        );

    PickImagesResult picks(
      List<PickedImage> images, {
      List<PickFileItemError> errors = const [],
    }) =>
        (images: images, errors: errors);

    Future<InlineImageComposerController> pumpComposer(
      WidgetTester tester, {
      Future<PickImagesResult?> Function()? openImagePicker,
      ReadonlySignal<AgentSessionState?>? sessionState,
    }) async {
      final controller = InlineImageComposerController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: ChatInput(
              onSend: (_) {},
              onCancel: () {},
              controller: controller,
              sessionState: sessionState,
              openImagePicker: openImagePicker,
            ),
          ),
        ),
      );
      return controller;
    }

    testWidgets('inserts each image at the caret, in selection order',
        (tester) async {
      final controller = await pumpComposer(
        tester,
        openImagePicker: () async => picks([
          pickedImage('a.png', 'image/png'),
          pickedImage('b.gif', 'image/gif', bytes: onePixelGif),
        ]),
      );

      await tester.enterText(find.byType(TextField), 'look at this');
      // Mid-text, so the images cannot arrive merely appended.
      controller.selection = const TextSelection.collapsed(offset: 7);
      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      final parts = controller.sendableParts();
      expect(
        parts?.map(
          (part) => switch (part) {
            TextPart(:final text) => text,
            ImagePart(:final mimeType) => mimeType,
            _ => 'unexpected',
          },
        ),
        ['look at', 'image/png', 'image/gif', ' this'],
      );
      // Nothing between the picker and the composer may alter the bytes: a
      // transform belongs behind the encoder, where it can be measured.
      expect(
        parts?.whereType<ImagePart>().map((part) => part.bytes),
        [onePixelPng, onePixelGif],
      );
    });

    testWidgets('says so when the picker itself fails', (tester) async {
      await pumpComposer(
        tester,
        openImagePicker: () async =>
            throw const PickFilePickerException(cause: 'no plugin'),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      // Not the upload path's "could not open file picker": on web the bytes
      // are read inside the picker call, so this failure is as likely to have
      // come after the chooser closed, which the user just watched work.
      expect(find.text('Could not add the images.'), findsOneWidget);
    });

    testWidgets('tells the user a browser pick was too large to load',
        (tester) async {
      // The web picker buffers every image whole, so this is the failure this
      // path is likeliest to hit, and 'try again' is advice that cannot work.
      await pumpComposer(
        tester,
        openImagePicker: () async =>
            throw PickFilePickerException(cause: RangeError('out of memory')),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(
        find.text('The images are too large to load in the browser.'),
        findsOneWidget,
      );
    });

    testWidgets('names a file it could not read', (tester) async {
      final controller = await pumpComposer(
        tester,
        openImagePicker: () async => picks(
          [],
          errors: const [
            PickFileItemError(filename: 'holiday.png', cause: 'gone'),
          ],
        ),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(controller.sendableParts(), isNull);
      expect(find.text('holiday.png could not be read.'), findsOneWidget);
    });

    testWidgets('reports what it could not attach and inserts none of it',
        (tester) async {
      final controller = await pumpComposer(
        tester,
        openImagePicker: () async => picks([
          pickedImage('scan.tiff', 'image/tiff'),
        ]),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(controller.sendableParts(), isNull);
      expect(find.text('scan.tiff is not a supported image.'), findsOneWidget);
    });

    testWidgets('counts the images already in the composer toward the limit',
        (tester) async {
      final controller = await pumpComposer(
        tester,
        openImagePicker: () async => picks([
          for (var i = 0; i < maxInlineImagesPerMessage; i++)
            pickedImage('image$i.png', 'image/png'),
        ]),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();
      expect(controller.sendableParts(), hasLength(maxInlineImagesPerMessage));

      // The limit is per message, not per pick: a second pick of the same size
      // must not double what the message carries.
      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(controller.sendableParts(), hasLength(maxInlineImagesPerMessage));
      expect(
        find.text(
          'A message carries at most $maxInlineImagesPerMessage images.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('drops a notice on a new conversation, still taking typing',
        (tester) async {
      // The notice describes a pick made into the conversation being left, so
      // it must not follow the user into the next one. It travels as a value
      // and not as a Key: re-inflating the composer would close the platform
      // text input connection while the caller-owned FocusNode survived, so
      // nothing would report a focus change, EditableText would never reopen
      // the connection, and typing would go nowhere.
      final controller = InlineImageComposerController();
      addTearDown(controller.dispose);
      final focusNode = FocusNode();
      addTearDown(focusNode.dispose);

      Widget app(Object scope) => MaterialApp(
            theme: soliplexLightTheme(),
            home: Scaffold(
              body: ChatInput(
                onSend: (_) {},
                onCancel: () {},
                controller: controller,
                focusNode: focusNode,
                composerScope: scope,
                openImagePicker: () async =>
                    picks([pickedImage('scan.tiff', 'image/tiff')]),
              ),
            ),
          );

      await tester.pumpWidget(app('thread-1'));
      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();
      expect(find.text('scan.tiff is not a supported image.'), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.pump();
      expect(tester.testTextInput.hasAnyClients, isTrue);

      await tester.pumpWidget(app('thread-2'));
      await tester.pumpAndSettle();

      expect(find.text('scan.tiff is not a supported image.'), findsNothing);
      expect(tester.testTextInput.hasAnyClients, isTrue,
          reason: 'the composer must keep the platform input connection');
      tester.testTextInput.enterText('still typing');
      await tester.pump();
      expect(controller.text, 'still typing');
    });

    testWidgets('leaves a cancelled pick to say nothing at all',
        (tester) async {
      // Backing out of the picker is the commonest thing that happens to it.
      // It is not a failure and has nothing to report, so it must not clear a
      // notice the user still needs to read.
      var cancel = false;
      final controller = await pumpComposer(
        tester,
        openImagePicker: () async =>
            cancel ? null : picks([pickedImage('scan.tiff', 'image/tiff')]),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();
      expect(find.text('scan.tiff is not a supported image.'), findsOneWidget);

      cancel = true;
      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(find.text('scan.tiff is not a supported image.'), findsOneWidget);
      expect(controller.sendableParts(), isNull);
      // And the button has to come back, or a cancel costs the user the
      // feature for the rest of the message.
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(
                IconButton,
                Icons.add_photo_alternate_outlined,
              ),
            )
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('speaks for a pick the platform lost entirely', (tester) async {
      // Android answers a pick it could not copy a single item out of with an
      // empty batch, having dropped the names on its side. Read as a cancel it
      // would leave the user tapping a button that does nothing.
      await pumpComposer(tester, openImagePicker: () async => picks([]));

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(
        find.text('Could not read the images you picked.'),
        findsOneWidget,
      );
    });

    testWidgets('leaves a pick behind in the conversation it was made into',
        (tester) async {
      // The composer outlives the conversation by design — it travels as a
      // value so the platform text input connection survives — so a pick that
      // was still open when the user moved on comes back to a composer that is
      // mounted, enabled, and now someone else's. Without a scope check the
      // images land in the wrong thread, and the next send carries them
      // somewhere the user never chose.
      final controller = InlineImageComposerController();
      addTearDown(controller.dispose);
      final gate = Completer<PickImagesResult?>();

      // Nothing on screen may speak for this pick, so the log has to. It is
      // the only account left of a file the picker could not read.
      final sink = MemorySink();
      LogManager.instance.addSink(sink);
      addTearDown(() => LogManager.instance.removeSink(sink));

      Widget app(Object scope) => MaterialApp(
            theme: soliplexLightTheme(),
            home: Scaffold(
              body: ChatInput(
                onSend: (_) {},
                onCancel: () {},
                controller: controller,
                composerScope: scope,
                openImagePicker: () => gate.future,
              ),
            ),
          );

      await tester.pumpWidget(app('thread-1'));
      await tester.tap(find.byTooltip('Add image'));
      await tester.pump();

      // What RoomScreen does on a thread change: same controller, cleared.
      controller.clear();
      await tester.pumpWidget(app('thread-2'));
      await tester.pump();

      gate.complete(
        picks(
          [pickedImage('a.png', 'image/png')],
          errors: const [
            PickFileItemError(filename: 'holiday.tiff', cause: 'gone'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(controller.sendableParts(), isNull,
          reason: 'the images belong to the conversation that was left');
      expect(find.text('holiday.tiff could not be read.'), findsNothing,
          reason: 'nor does what that pick had to say about itself');
      expect(
        sink.records.where((r) => r.attributes['filename'] == 'holiday.tiff'),
        isNotEmpty,
        reason: 'the log is the only place that file is still accounted for',
      );
    });

    testWidgets('drops a notice once a later pick has nothing to report',
        (tester) async {
      var reject = true;
      final controller = await pumpComposer(
        tester,
        openImagePicker: () async => reject
            ? picks([pickedImage('scan.tiff', 'image/tiff')])
            : picks([pickedImage('a.png', 'image/png')]),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();
      expect(find.text('scan.tiff is not a supported image.'), findsOneWidget);

      reject = false;
      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(find.text('scan.tiff is not a supported image.'), findsNothing);
      expect(controller.sendableParts(), hasLength(1));
    });

    testWidgets('refuses to add images to a composer a run has taken',
        (tester) async {
      // The picker can outlive the composer's availability, and an image put
      // into a read-only composer cannot be taken back out of it — the chip
      // showing a picture has no remove affordance — so it would be sent with
      // whatever the user typed next.
      final sessionState = signal<AgentSessionState?>(null);
      addTearDown(sessionState.dispose);
      final controller = await pumpComposer(
        tester,
        sessionState: sessionState,
        openImagePicker: () async {
          sessionState.value = AgentSessionState.running;
          return picks([pickedImage('a.png', 'image/png')]);
        },
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(controller.sendableParts(), isNull);
      expect(
        find.text('The composer was busy. Add the images again.'),
        findsOneWidget,
      );
    });

    testWidgets('is disabled while a run holds the composer', (tester) async {
      final sessionState = signal<AgentSessionState?>(
        AgentSessionState.running,
      );
      addTearDown(sessionState.dispose);
      await pumpComposer(tester, sessionState: sessionState);

      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(
                IconButton,
                Icons.add_photo_alternate_outlined,
              ),
            )
            .onPressed,
        isNull,
      );
    });

    testWidgets('drops a notice once the message it sat above is sent',
        (tester) async {
      // The notice describes a pick into a message that has now gone; leaving
      // it would strand an error above an empty composer with nothing to
      // explain it.
      await pumpComposer(
        tester,
        openImagePicker: () async =>
            picks([pickedImage('scan.tiff', 'image/tiff')]),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();
      expect(find.text('scan.tiff is not a supported image.'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'never mind');
      await tester.pump();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();

      expect(find.text('scan.tiff is not a supported image.'), findsNothing);
    });

    testWidgets('says so when the picker fails in a way it cannot name',
        (tester) async {
      // Nothing in the app installs a global async error handler, so a throw
      // this does not catch would leave the button looking dead: no images, no
      // notice, and no log line for anyone to work back from.
      await pumpComposer(
        tester,
        openImagePicker: () async => throw StateError('plugin blew up'),
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pumpAndSettle();

      expect(find.text('Could not add the images.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('opens one picker however often the button is tapped',
        (tester) async {
      // A second pick while the first is open is answered by the Android
      // plugin with an "already active" error, which would report a failure
      // over a pick that is still working.
      var opens = 0;
      final gate = Completer<PickImagesResult?>();
      await pumpComposer(
        tester,
        openImagePicker: () {
          opens++;
          return gate.future;
        },
      );

      await tester.tap(find.byTooltip('Add image'));
      await tester.pump();
      await tester.tap(find.byTooltip('Add image'), warnIfMissed: false);
      await tester.pump();

      expect(opens, 1);

      gate.complete(picks([pickedImage('a.png', 'image/png')]));
      await tester.pumpAndSettle();

      // The button comes back once the pick is done.
      await tester.tap(find.byTooltip('Add image'));
      await tester.pump();
      expect(opens, 2);
    });
  });

  group('leading controls', () {
    Widget composer({
      required double width,
      required InlineImageComposerController controller,
      bool filter = false,
      bool upload = false,
      bool folder = true,
      VoidCallback? onFilter,
      VoidCallback? onFiles,
      VoidCallback? onFolder,
      ReadonlySignal<AgentSessionState?>? sessionState,
    }) =>
        MaterialApp(
          theme: soliplexLightTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: width,
                child: ChatInput(
                  onSend: (_) {},
                  onCancel: () {},
                  controller: controller,
                  sessionState: sessionState,
                  onFilterTap: filter ? (onFilter ?? () {}) : null,
                  onAttachFile: upload ? (onFiles ?? () {}) : null,
                  onAttachFolder: upload && folder ? (onFolder ?? () {}) : null,
                ),
              ),
            ),
          ),
        );

    InlineImageComposerController newController() {
      final controller = InlineImageComposerController();
      addTearDown(controller.dispose);
      return controller;
    }

    testWidgets('a narrow composer shows the filter alone directly',
        (tester) async {
      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.mobile,
          controller: newController(),
          filter: true,
        ),
      );

      expect(find.byTooltip('Filter documents'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('a narrow composer shows upload alone directly',
        (tester) async {
      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.mobile,
          controller: newController(),
          upload: true,
        ),
      );

      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets(
        'a narrow composer collapses the filter and upload pair into one menu',
        (tester) async {
      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.mobile,
          controller: newController(),
          filter: true,
          upload: true,
        ),
      );

      // Three leading buttons, the gap and send leave a 320 px composer a
      // 104 px text field, so the optional pair shares a slot.
      expect(find.byTooltip('Add image'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt), findsNothing);
      expect(find.byIcon(Icons.attach_file), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      // Flattened, not nested: upload is a menu of its own, and Material
      // handles a menu inside a menu poorly.
      expect(find.text('Filter documents'), findsOneWidget);
      expect(find.text('Upload files…'), findsOneWidget);
      expect(find.text('Upload folder…'), findsOneWidget);
    });

    testWidgets('each collapsed item runs the action it names', (tester) async {
      // The items lose their icons on the way into the menu, so nothing but
      // this says a label still reaches the action it was written for.
      final ran = <String>[];
      Future<void> choose(String label) async {
        await tester.pumpWidget(
          composer(
            width: SoliplexBreakpoints.mobile,
            controller: newController(),
            filter: true,
            upload: true,
            onFilter: () => ran.add('filter'),
            onFiles: () => ran.add('files'),
            onFolder: () => ran.add('folder'),
          ),
        );
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
      }

      await choose('Filter documents');
      await choose('Upload files…');
      await choose('Upload folder…');

      expect(ran, ['filter', 'files', 'folder']);
    });

    testWidgets('a composer with no folder picker collapses to two items',
        (tester) async {
      // A caller that offers file upload but no folder pick: the pair still
      // collapses, and the menu carries one upload item.
      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.mobile,
          controller: newController(),
          filter: true,
          upload: true,
          folder: false,
        ),
      );

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.text('Filter documents'), findsOneWidget);
      expect(find.text('Upload files…'), findsOneWidget);
      expect(find.text('Upload folder…'), findsNothing);
    });

    testWidgets('a run holding the composer disables the collapsed menu',
        (tester) async {
      // The buttons this menu stands in for are gated during a run; hiding
      // them behind a menu must not be the way around that.
      final sessionState =
          signal<AgentSessionState?>(AgentSessionState.running);
      addTearDown(sessionState.dispose);

      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.mobile,
          controller: newController(),
          filter: true,
          upload: true,
          sessionState: sessionState,
        ),
      );

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      expect(find.text('Filter documents'), findsNothing);
      expect(find.text('Upload files…'), findsNothing);
    });

    testWidgets('a tablet-width composer shows all three individually',
        (tester) async {
      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.tablet,
          controller: newController(),
          filter: true,
          upload: true,
        ),
      );

      expect(find.byTooltip('Add image'), findsOneWidget);
      expect(find.byIcon(Icons.filter_alt), findsOneWidget);
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsNothing);
    });

    testWidgets('the field keeps its width when the document filter appears',
        (tester) async {
      // The room reveals the filter once its document load lands, which can
      // happen while the user is typing. Collapsing the optional pair is what
      // holds the row at two leading slots across that change. Upload is
      // present because that is the case the row holds steady: with no upload
      // affordance the filter's arrival still takes the row from one slot to
      // two.
      final controller = newController();
      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.mobile,
          controller: controller,
          upload: true,
        ),
      );
      final before = tester.getSize(find.byType(TextField)).width;

      await tester.pumpWidget(
        composer(
          width: SoliplexBreakpoints.mobile,
          controller: controller,
          upload: true,
          filter: true,
        ),
      );

      expect(tester.getSize(find.byType(TextField)).width, before);
    });
  });
}
