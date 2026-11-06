import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';

import 'package:soliplex_frontend/src/modules/room/file_sort.dart';
import 'package:soliplex_frontend/src/modules/room/ui/collapse_folders_button.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workspace_files_section.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

import '../../../helpers/file_name_finder.dart';
import '../../../helpers/test_downloads.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

/// The button above the workspace list, sharing the folder toggles the way
/// the room's controller holds them, so a tap on either takes effect.
Widget _panel(
  List<String> paths, {
  FileSort sort = FileSort.foldersAToZ,
  Map<String, bool> toggles = const {},
}) {
  final files = [for (final p in paths) _file(p)];
  var held = toggles;
  return MaterialApp(
    theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
    home: Scaffold(
      body: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setState) => Column(
            children: [
              CollapseFoldersButton(
                listing: files,
                sort: sort,
                folderToggles: held,
                onCollapse: (folders) => setState(
                  () => held = {...held, for (final f in folders) f: false},
                ),
              ),
              WorkspaceFilesSection(
                status: WorkdirFilesLoaded(files),
                sort: sort,
                downloads: testDownloads(),
                onFetchBytes: (_) async => Uint8List(0),
                onRetry: () {},
                folderToggles: held,
                onFolderToggled: (folder, {required expanded}) =>
                    setState(() => held = {...held, folder: expanded}),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  SemanticsData semantics(WidgetTester tester) => tester
      .getSemantics(find.bySemanticsLabel(RegExp('^Collapse all folders')))
      .getSemanticsData();

  testWidgets('shows nothing for a workspace without folders', (tester) async {
    await tester.pumpWidget(_panel(['a.txt', 'b.txt']));

    expect(find.byIcon(Icons.unfold_less), findsNothing);
  });

  testWidgets('closes every open folder, nested ones too', (tester) async {
    await tester.pumpWidget(_panel(
      ['src/main.py', 'src/lib/util.py', 'docs/a.md'],
      toggles: {'src/lib': true},
    ));
    expect(findFileName('util.py'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.unfold_less));
    await tester.pump();

    expect(findFileName('main.py'), findsNothing);
    expect(findFileName('a.md'), findsNothing);

    await tester.tap(find.text('src'));
    await tester.pump();

    expect(findFileName('main.py'), findsOneWidget);
    expect(findFileName('util.py'), findsNothing,
        reason: 'lib was closed too, so reopening src shows it closed');
  });

  testWidgets('names what it does to a screen reader and on hover',
      (tester) async {
    await tester.pumpWidget(_panel(['src/main.py']));

    final data = semantics(tester);
    expect(data.label, 'Collapse all folders');
    expect(data.flagsCollection.isEnabled.toBoolOrNull(), isTrue);
    expect(find.byTooltip('Collapse all folders'), findsOneWidget);
  });

  testWidgets('is disabled, saying why, once no folder is open',
      (tester) async {
    await tester.pumpWidget(_panel(['src/main.py'], toggles: {'src': false}));

    final data = semantics(tester);
    expect(data.label, 'Collapse all folders: No folder is open');
    expect(data.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
    expect(find.byTooltip('No folder is open'), findsOneWidget);
  });

  testWidgets('leaves alone an open folder inside a closed one',
      (tester) async {
    await tester.pumpWidget(_panel(
      ['src/main.py', 'src/lib/util.py'],
      toggles: {'src': false, 'src/lib': true},
    ));
    expect(
      semantics(tester).label,
      'Collapse all folders: No folder is open',
      reason: 'nothing open is in view',
    );

    await tester.tap(find.byIcon(Icons.unfold_less));
    await tester.pump();
    await tester.tap(find.text('src'));
    await tester.pump();

    expect(findFileName('util.py'), findsOneWidget,
        reason: 'lib stays open behind its closed parent');
  });

  testWidgets('is disabled, saying why, under a flat order', (tester) async {
    await tester.pumpWidget(_panel(['src/main.py'], sort: FileSort.nameAToZ));

    final data = semantics(tester);
    expect(data.label, 'Collapse all folders: Folders show only under Folders');
    expect(data.flagsCollection.isEnabled.toBoolOrNull(), isFalse);
  });
}
