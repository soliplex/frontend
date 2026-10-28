import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:signals_flutter/signals_flutter.dart';
import 'package:soliplex_client/soliplex_client.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/room/ui/workspace_event_banner.dart';
import 'package:soliplex_frontend/src/modules/room/workdir_files_status.dart';

WorkdirFile _file(String name) =>
    WorkdirFile(filename: name, url: Uri.parse('https://example.test/$name'));

WorkdirFilesLoaded _loaded(List<String> names) =>
    WorkdirFilesLoaded([for (final n in names) _file(n)]);

Widget _banner(
  ReadonlySignal<WorkdirFilesStatus> status, {
  String threadId = 't-1',
}) =>
    MaterialApp(
      theme: lowerBrandTheme(const BrandTheme.soliplex(), Brightness.light),
      home: Scaffold(
        body: WorkspaceEventBanner(
          status: status,
          threadId: threadId,
          onShow: () {},
        ),
      ),
    );

void main() {
  late Signal<WorkdirFilesStatus> status;

  setUp(() {
    status = Signal<WorkdirFilesStatus>(const WorkdirFilesLoading());
  });

  tearDown(() => status.dispose());

  Finder pillText() => find.textContaining('to the workspace');

  /// Lands [names] as the thread's baseline listing.
  Future<void> enterWith(WidgetTester tester, List<String> names) async {
    await tester.pumpWidget(_banner(status));
    status.value = _loaded(names);
    await tester.pump();
  }

  testWidgets('entering a thread that has files shows nothing', (tester) async {
    await enterWith(tester, ['a.csv', 'b.csv']);

    expect(pillText(), findsNothing);
  });

  testWidgets('a listing already loaded at mount is the baseline',
      (tester) async {
    status.value = _loaded(['a.csv']);
    await tester.pumpWidget(_banner(status));
    await tester.pump();

    expect(pillText(), findsNothing);
  });

  testWidgets('one added file names it', (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value = _loaded(['a.csv', 'report.csv']);
    await tester.pump();

    expect(find.text('Added report.csv to the workspace'), findsOneWidget);
  });

  testWidgets('a nested file is named by its basename', (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value = _loaded(['a.csv', 'reports/chart.png']);
    await tester.pump();

    expect(find.text('Added chart.png to the workspace'), findsOneWidget);
  });

  testWidgets('added files that share a basename count as two', (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value = _loaded(['a.csv', 'a/x.csv', 'b/x.csv']);
    await tester.pump();

    expect(
        find.text('Added x.csv and 1 more to the workspace'), findsOneWidget);
  });

  testWidgets('files added under .git or __pycache__ are not announced',
      (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value =
        _loaded(['a.csv', '.git/HEAD', 'crm_app/x/__pycache__/v.pyc']);
    await tester.pump();

    expect(pillText(), findsNothing);
  });

  testWidgets('files added under .git or __pycache__ are left out of the count',
      (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value = _loaded(['a.csv', '.git/HEAD', 'reports/chart.png']);
    await tester.pump();

    expect(find.text('Added chart.png to the workspace'), findsOneWidget);
  });

  testWidgets('several added files name the first and count the rest',
      (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value = _loaded(['a.csv', 'report.csv', 'x.png', 'y.png']);
    await tester.pump();

    expect(
      find.text('Added report.csv and 2 more to the workspace'),
      findsOneWidget,
    );
  });

  testWidgets('an unchanged or shrunk listing shows nothing', (tester) async {
    await enterWith(tester, ['a.csv', 'b.csv']);

    status.value = _loaded(['a.csv', 'b.csv']);
    await tester.pump();
    expect(pillText(), findsNothing);

    status.value = _loaded(['a.csv']);
    await tester.pump();
    expect(pillText(), findsNothing);
  });

  testWidgets('Loading and Failed neither fire nor reset the baseline',
      (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value = const WorkdirFilesLoading();
    await tester.pump();
    status.value = const WorkdirFilesFailed('boom');
    await tester.pump();

    status.value = _loaded(['a.csv', 'b.csv']);
    await tester.pump();

    expect(find.text('Added b.csv to the workspace'), findsOneWidget,
        reason: 'a.csv was in the baseline, so only b.csv is new');
  });

  testWidgets('a second batch before dismissal joins the first',
      (tester) async {
    await enterWith(tester, ['a.csv']);

    status.value = _loaded(['a.csv', 'c.csv']);
    await tester.pump();
    status.value = _loaded(['a.csv', 'b.csv', 'c.csv']);
    await tester.pump();

    expect(
      find.text('Added b.csv and 1 more to the workspace'),
      findsOneWidget,
    );
  });

  testWidgets('after a dismissal the next batch names only its own files',
      (tester) async {
    await enterWith(tester, ['a.csv']);
    status.value = _loaded(['a.csv', 'b.csv']);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    status.value = _loaded(['a.csv', 'b.csv', 'c.csv']);
    await tester.pump();

    expect(find.text('Added c.csv to the workspace'), findsOneWidget);
  });

  testWidgets('a thread change clears the pill and re-baselines',
      (tester) async {
    await enterWith(tester, ['a.csv']);
    status.value = _loaded(['a.csv', 'b.csv']);
    await tester.pump();
    expect(pillText(), findsOneWidget, reason: 'precondition');

    final other = Signal<WorkdirFilesStatus>(_loaded(['x.csv']));
    addTearDown(other.dispose);
    await tester.pumpWidget(_banner(other, threadId: 't-2'));
    await tester.pumpAndSettle();
    expect(pillText(), findsNothing);

    other.value = _loaded(['x.csv', 'y.csv']);
    await tester.pump();

    expect(find.text('Added y.csv to the workspace'), findsOneWidget);
  });

  testWidgets('dismisses itself after 4 seconds', (tester) async {
    await enterWith(tester, ['a.csv']);
    status.value = _loaded(['a.csv', 'b.csv']);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 3900));
    expect(pillText(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
    expect(pillText(), findsNothing);
  });

  testWidgets('the close button dismisses it', (tester) async {
    await enterWith(tester, ['a.csv']);
    status.value = _loaded(['a.csv', 'b.csv']);
    await tester.pump();

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(pillText(), findsNothing);
  });

  testWidgets('Show dismisses the pill', (tester) async {
    await enterWith(tester, ['a.csv']);
    status.value = _loaded(['a.csv', 'b.csv']);
    await tester.pump();

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();

    expect(pillText(), findsNothing);
  });
}
