import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soliplex_frontend/src/modules/room/ui/room_info/expandable_list_card.dart';
import 'package:soliplex_frontend/src/modules/room/ui/room_info/room_info_widgets.dart';

void main() {
  testWidgets('an expanded tile collapses when its content is tapped',
      (tester) async {
    // The whole tile is the toggle, so a tap anywhere over an InfoRow has to
    // reach it. A selection-aware widget in the value column silently wins the
    // gesture arena and leaves most of the row dead to taps.
    var toggles = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ExpandableTile(
            name: 'search_documents',
            expanded: true,
            onToggle: () => toggles++,
            content: const InfoRow(label: 'Allow MCP', value: 'Yes'),
          ),
        ),
      ),
    );

    final value = tester.getRect(find.text('Yes'));
    // Far from any glyph: `Expanded` stretches the value column across the
    // tile, so this lands in empty space that still belongs to the row.
    await tester.tapAt(Offset(value.right - 8, value.center.dy));
    await tester.pump();

    expect(toggles, 1);
  });
}
