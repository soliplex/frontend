import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soliplex_frontend/src/mockups/datasets/classification_levels.dart';
import 'package:soliplex_frontend/src/mockups/datasets/datasets_mockup.dart';
import 'package:soliplex_frontend/src/mockups/mockup.dart';
import 'package:soliplex_frontend/src/mockups/mockup_app.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  final mockup = Mockup(
    name: 'Datasets',
    classifications: mockupClassifications,
    build: (_) => const DatasetsMockup(),
  );

  Future<void> open(WidgetTester tester, {double width = 1280}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MockupApp(mockups: [mockup], initial: mockup));
    await tester.pumpAndSettle();
  }

  testWidgets('the lobby shows room presets and switches to the catalog',
      (tester) async {
    await open(tester);
    expect(find.text('Plant Maintenance'), findsOneWidget);
    expect(find.text('Room level'), findsNWidgets(3));
    expect(find.text('INTERNAL'), findsWidgets);

    await tester.tap(find.text('Datasets').last);
    await tester.pumpAndSettle();
    expect(find.textContaining(' datasets'), findsWidgets);
    expect(find.text('New dataset'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Search datasets, tags, systems…'),
      'relief valve',
    );
    await tester.pumpAndSettle();
    expect(find.text('Relief valve systems'), findsOneWidget);
    expect(find.text('Lockout/tagout checklists'), findsNothing);
  });

  testWidgets('create, upload, scan and commit — gated on the attestation',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Datasets').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('New dataset'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Pump notes',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'Pump notes',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('jdoe/pump-notes'), findsOneWidget);
    await tester.tap(find.text('INTERNAL').last);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Create dataset'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('Create dataset'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No files yet'), findsOneWidget);
    await tester.tap(find.text('Upload to dataset').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add sample files'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan 6 files'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.textContaining("It won't be added"), findsOneWidget);
    expect(
        find.textContaining('Possible CONFIDENTIAL markings'), findsOneWidget);
    // A flag nobody has looked at holds the upload back.
    final next = find.widgetWithText(FilledButton, 'Continue to review');
    expect(tester.widget<FilledButton>(next).onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continue to review'));
    await tester.pumpAndSettle();

    expect(find.textContaining('5 files will be added'), findsOneWidget);
    final commit = find.widgetWithText(FilledButton, 'Commit 5 files');
    expect(tester.widget<FilledButton>(commit).onPressed, isNull);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commit 5 files'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('5 files · '), findsOneWidget);
    expect(find.textContaining('raw files only'), findsWidgets);
    // Let ingestion run out before the test ends.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Searchable'), findsWidgets);
  });

  testWidgets(
      "anyone with access uploads, and a file is marked outdated, not "
      'removed', (tester) async {
    await open(tester);
    await tester.tap(find.text('Datasets').last);
    await tester.pumpAndSettle();
    // Someone else's dataset: the upload is still there.
    await tester.enterText(
      find.widgetWithText(TextField, 'Search datasets, tags, systems…'),
      'pump service manuals',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pump service manuals'));
    await tester.pumpAndSettle();
    expect(find.text('Upload to dataset'), findsOneWidget);
    expect(find.textContaining('1 marked outdated'), findsOneWidget);
    expect(find.text('Outdated'), findsOneWidget);

    await tester.tap(find.byTooltip('File actions').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark outdated…'));
    await tester.pumpAndSettle();
    FilledButton mark() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Mark outdated'),
        );
    expect(mark().onPressed, isNull);
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason (required)'),
      'Wrong revision',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Mark outdated'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2 marked outdated'), findsOneWidget);
    expect(find.text('Outdated'), findsNWidgets(2));

    await tester.tap(find.text('Upload to dataset'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('attach it in the thread instead'), findsOneWidget);
    expect(find.text('Choose folder…'), findsOneWidget);
  });

  testWidgets('sharing waits for an audience, tags and the attestation',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Datasets').last);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search datasets, tags, systems…'),
      'vibration',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Vibration inspection notes'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Share'));
    await tester.pumpAndSettle();

    FilledButton share() => tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Share'),
        );
    expect(share().onPressed, isNull);

    await tester.tap(find.text('Plant/Maintenance'));
    // Cleared below INTERNAL: can't be picked.
    await tester.scrollUntilVisible(
      find.textContaining("wouldn't have access"),
      100,
      scrollable: find
          .descendant(
              of: find.byType(Dialog), matching: find.byType(Scrollable))
          .first,
    );
    await tester.ensureVisible(find.widgetWithText(TextField, 'Keywords'));
    await tester.enterText(
      find.widgetWithText(TextField, 'Keywords'),
      'vibration',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.ensureVisible(
      find.widgetWithText(TextField, 'System / equipment'),
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'System / equipment'),
      'P-100',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(share().onPressed, isNull);

    await tester.ensureVisible(find.textContaining('I confirm everyone'));
    await tester.tap(find.textContaining('I confirm everyone'));
    await tester.pumpAndSettle();
    expect(share().onPressed, isNotNull);
    await tester.tap(find.widgetWithText(FilledButton, 'Share'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Shared jdoe/inspection-notes'), findsOneWidget);
  });

  testWidgets(
      'a thread starts from the room defaults, locks on the first message, '
      'and a new thread takes its datasets', (tester) async {
    await open(tester);
    await tester.tap(find.text('Plant Maintenance'));
    await tester.pumpAndSettle();

    // Lands on the room's latest thread, which has started: fixed.
    expect(find.text('2 in use · fixed'), findsOneWidget);
    expect(find.text('New thread with these datasets'), findsOneWidget);
    expect(find.byTooltip('Remove from this thread'), findsNothing);

    await tester.ensureVisible(find.text('New thread with these datasets'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New thread with these datasets'));
    await tester.pumpAndSettle();
    expect(find.text('2 in use'), findsOneWidget);
    expect(find.text('Add datasets'), findsOneWidget);

    // Add a pinned dataset with one tap.
    await tester.tap(find.text('ops/maintenance-trend-data'));
    await tester.pumpAndSettle();
    expect(find.text('3 in use'), findsOneWidget);

    // The picker shows what is above the room's level locked.
    await tester.tap(find.text('Add datasets'));
    await tester.pumpAndSettle();
    // Turn "Within room level" off: the only switch that is on.
    await tester.tap(
      find.byWidgetPredicate((w) => w is Switch && w.value),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Search datasets, tags, systems…').last,
      'playbook',
    );
    await tester.pumpAndSettle();
    expect(find.textContaining("Above this room's level"), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, 'Where do I start?');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('3 in use · fixed'), findsOneWidget);
  });

  testWidgets('narrow: the composer summary opens the datasets sheet',
      (tester) async {
    await open(tester, width: 400);
    await tester.tap(find.text('Plant Maintenance'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('2 datasets'));
    await tester.pumpAndSettle();
    expect(find.text('Datasets'), findsWidgets);
    expect(find.text('New thread with these datasets'), findsOneWidget);
  });
}
