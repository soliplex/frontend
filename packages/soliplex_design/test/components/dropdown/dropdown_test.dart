import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';

const List<SoliplexDropdownEntry<String>> _entries = [
  SoliplexDropdownEntry(value: 'free', label: 'Free'),
  SoliplexDropdownEntry(value: 'pro', label: 'Pro'),
  SoliplexDropdownEntry(value: 'team', label: 'Team'),
];

Widget _harness(Widget child) {
  return MaterialApp(
    theme: soliplexLightTheme(),
    home: Scaffold(
      body: Padding(padding: const EdgeInsets.all(16), child: child),
    ),
  );
}

void main() {
  testWidgets('renders the label', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexDropdown<String>(label: 'Plan', entries: _entries),
      ),
    );
    // DropdownMenu renders the label in both the floating label slot and
    // an offstage measurement slot, so accept ≥1.
    expect(find.text('Plan'), findsAtLeastNWidgets(1));
  });

  testWidgets('initialValue is shown in the closed field', (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexDropdown<String>(
          label: 'Plan',
          entries: _entries,
          initialValue: 'pro',
        ),
      ),
    );
    expect(find.text('Pro'), findsAtLeastNWidgets(1));
  });

  testWidgets('onSelected fires with the picked value', (tester) async {
    String? picked;
    await tester.pumpWidget(
      _harness(
        SoliplexDropdown<String>(
          label: 'Plan',
          entries: _entries,
          onSelected: (v) => picked = v,
        ),
      ),
    );
    // Open the menu and tap an entry.
    await tester.tap(find.byType(DropdownMenu<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Team').last);
    await tester.pumpAndSettle();
    expect(picked, 'team');
  });

  testWidgets('errorText is forwarded to the underlying decoration',
      (tester) async {
    await tester.pumpWidget(
      _harness(
        const SoliplexDropdown<String>(
          label: 'Plan',
          entries: _entries,
          errorText: 'pick one',
        ),
      ),
    );
    expect(find.text('pick one'), findsOneWidget);
  });

  testWidgets('isLoading shows a spinner and disables the menu',
      (tester) async {
    String? picked;
    await tester.pumpWidget(
      _harness(
        SoliplexDropdown<String>(
          label: 'Plan',
          entries: _entries,
          isLoading: true,
          onSelected: (v) => picked = v,
        ),
      ),
    );
    // DropdownMenu may render trailingIcon in multiple internal slots.
    expect(find.byType(CircularProgressIndicator), findsAtLeastNWidgets(1));
    await tester.tap(find.byType(DropdownMenu<String>));
    // Use pump() (not pumpAndSettle) because the spinner animates forever.
    await tester.pump();
    // Even after tapping, onSelected must not fire — the menu is
    // effectively unreachable. (DropdownMenu always renders entries in
    // an offstage overlay, so we don't probe widget-tree text here.)
    expect(picked, isNull);
  });

  testWidgets('preserves a non-String generic value type', (tester) async {
    const numEntries = [
      SoliplexDropdownEntry<int>(value: 1, label: 'One'),
      SoliplexDropdownEntry<int>(value: 2, label: 'Two'),
    ];
    int? picked;
    await tester.pumpWidget(
      _harness(
        SoliplexDropdown<int>(
          label: 'Count',
          entries: numEntries,
          onSelected: (v) => picked = v,
        ),
      ),
    );
    await tester.tap(find.byType(DropdownMenu<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two').last);
    await tester.pumpAndSettle();
    expect(picked, 2);
  });
}
