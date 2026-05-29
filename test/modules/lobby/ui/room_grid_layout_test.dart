import 'package:flutter_test/flutter_test.dart';
import 'package:soliplex_design/soliplex_design.dart';
import 'package:soliplex_frontend/src/modules/lobby/ui/room_grid_layout.dart';

void main() {
  group('roomGridLayout columns', () {
    test('one column below the mobile breakpoint', () {
      expect(roomGridLayout(SoliplexBreakpoints.mobile - 1).columns, 1);
    });

    test('two columns from the mobile breakpoint up to desktop', () {
      expect(roomGridLayout(SoliplexBreakpoints.mobile).columns, 2);
      expect(roomGridLayout(SoliplexBreakpoints.desktop - 1).columns, 2);
    });

    test('three columns at the desktop breakpoint and wider', () {
      expect(roomGridLayout(SoliplexBreakpoints.desktop).columns, 3);
      expect(roomGridLayout(SoliplexBreakpoints.desktop + 200).columns, 3);
    });
  });

  group('roomGridLayout cellWidth', () {
    test('fills the full width in a single column', () {
      expect(roomGridLayout(300, spacing: 12).cellWidth, 300);
    });

    test('subtracts the inter-cell gaps before dividing', () {
      // Two columns: one gap. (600 - 12) / 2.
      expect(roomGridLayout(600, spacing: 12).cellWidth, 294);
      // Three columns: two gaps. (840 - 24) / 3.
      expect(roomGridLayout(840, spacing: 12).cellWidth, 272);
    });
  });
}
